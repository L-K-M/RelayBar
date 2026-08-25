import Foundation
import CAppIndicator

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Process-wide shutdown state, reachable from signal handlers that cannot
/// capture context.
final class Shutdown: @unchecked Sendable {
    static let shared = Shutdown()

    private let lock = NSLock()
    private var handler: (() -> Void)?

    func setHandler(_ newHandler: @escaping () -> Void) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    /// Idempotent: the handler runs once; later requests are ignored.
    func request() {
        lock.lock()
        let currentHandler = handler
        handler = nil
        lock.unlock()
        currentHandler?()
    }
}

/// Keeps DispatchSourceSignal instances alive for the process lifetime;
/// deallocated sources silently stop delivering.
private final class SourceRetention: @unchecked Sendable {
    static let shared = SourceRetention()

    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []

    func hold(_ source: DispatchSourceSignal) {
        lock.lock()
        sources.append(source)
        lock.unlock()
    }
}

enum CommandLineOutcome {
    case help(String)
    case invalid(String)
    case valid(configPath: String, sshPath: String)
}

enum Options {
    static func parse(_ arguments: [String]) -> CommandLineOutcome {
        var configPath = ProfileStore.defaultFileURL().path
        var sshPath = "/usr/bin/ssh"

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                return .help(usageText)
            case "--config":
                guard index + 1 < arguments.count else {
                    return .invalid("--config requires a path")
                }
                index += 1
                configPath = arguments[index]
            case "--ssh-path":
                guard index + 1 < arguments.count else {
                    return .invalid("--ssh-path requires a path")
                }
                index += 1
                sshPath = arguments[index]
            default:
                return .invalid("unknown argument \(arguments[index])")
            }
            index += 1
        }
        return .valid(configPath: configPath, sshPath: sshPath)
    }

    static var usageText: String {
        """
        relaybar-tray — RelayBar Scion system tray for Linux

        Usage: relaybar-tray [--config PATH] [--ssh-path PATH]

          --config PATH   Profile file (a JSON array of RelayBar tunnels);
                          defaults to $XDG_CONFIG_HOME/relaybar/tunnels.json
          --ssh-path PATH OpenSSH binary; defaults to /usr/bin/ssh
        """
    }
}

func run(arguments: [String]) -> Int32 {
    switch Options.parse(arguments) {
    case .help(let text):
        print(text)
        return EXIT_SUCCESS
    case .invalid(let message):
        FileHandle.standardError.write(
            Data("relaybar-tray: \(message)\n\n\(Options.usageText)\n".utf8)
        )
        return EX_USAGE
    case .valid(let configPath, let sshPath):
        // SIGINT/SIGTERM must tear down managed ssh masters before exiting.
        // Signal disposition is ignored first so the default termination can
        // never win a race against the dispatch source.
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: DispatchQueue.global()
            )
            source.setEventHandler { Shutdown.shared.request() }
            source.resume()
            SourceRetention.shared.hold(source)
        }

        let store = ProfileStore(fileURL: URL(fileURLWithPath: configPath))
        let supervisor = TunnelSupervisor(sshExecutableURL: URL(fileURLWithPath: sshPath))
        supervisor.replaceProfiles(store.load())

        let menu = TrayMenuController(supervisor: supervisor, profileStore: store)
        // The menu controller must outlive run(); keep the reference explicit.
        _ = menu

        let loop = relaybar_main_loop_new()
        Shutdown.shared.setHandler { [weak supervisor] in
            supervisor?.stopAll()
            if let loop {
                relaybar_main_loop_quit(loop)
            }
        }

        relaybar_main_loop_run(loop)
        return EXIT_SUCCESS
    }
}

exit(run(arguments: CommandLine.arguments))
