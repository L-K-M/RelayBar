import AppKit
import Combine
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

enum UpdateCheckResult: Equatable {
    case available
    case upToDate
    case failed
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case failed
    case waitingForTunnels(Int)
}

@MainActor
protocol UpdateServicing: AnyObject {
    var isAvailable: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var deferredInstallTunnelCount: Int? { get }
    var stateDidChange: (@MainActor () -> Void)? { get set }

    func start()
    func checkForUpdates(
        completion: @escaping @MainActor (UpdateCheckResult) -> Void
    )
    func prepareForApplicationTermination() -> Bool
}

@MainActor
final class UnavailableUpdateService: UpdateServicing {
    let isAvailable = false
    var automaticallyChecksForUpdates = false
    var canCheckForUpdates: Bool { false }
    var deferredInstallTunnelCount: Int? { nil }
    var stateDidChange: (@MainActor () -> Void)?

    func start() {}

    func checkForUpdates(
        completion: @escaping @MainActor (UpdateCheckResult) -> Void
    ) {
        completion(.failed)
    }

    func prepareForApplicationTermination() -> Bool { false }
}

enum MaintainerUpdateFeed {
    static let launchArgument = "--maintainer-update-feed"

    static func urlString(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        let argumentIndexes = arguments.indices.filter {
            arguments[$0] == launchArgument
        }
        guard
            argumentIndexes.count == 1,
            arguments.indices.contains(argumentIndexes[0] + 1)
        else {
            return nil
        }
        return validatedURLString(arguments[argumentIndexes[0] + 1])
    }

    static func wasRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(launchArgument)
    }

    static func validatedURLString(_ candidate: String?) -> String? {
        guard
            let candidate,
            let components = URLComponents(string: candidate),
            components.scheme == "http",
            let rawHost = components.host?.lowercased(),
            components.port != nil,
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            !components.path.isEmpty
        else {
            return nil
        }
        let host = rawHost.trimmingCharacters(
            in: CharacterSet(charactersIn: "[]")
        )
        guard ["127.0.0.1", "localhost", "::1"].contains(host) else {
            return nil
        }
        return components.string
    }
}

enum UpdateInstallDecision {
    case stopAndInstall
    case waitForTunnels
}

@MainActor
protocol UpdateInstallPrompting {
    func decision(activeTunnelCount: Int) -> UpdateInstallDecision
}

@MainActor
struct SystemUpdateInstallPrompt: UpdateInstallPrompting {
    func decision(activeTunnelCount: Int) -> UpdateInstallDecision {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "RelayBar Update Is Ready"
        let noun = activeTunnelCount == 1 ? "tunnel" : "tunnels"
        alert.informativeText = "RelayBar downloaded the update. \(activeTunnelCount) active \(noun) must stop before the app can relaunch."
        alert.addButton(
            withTitle: "Stop \(activeTunnelCount) \(noun.capitalized) and Relaunch"
        )
        alert.addButton(withTitle: "Wait for \(noun.capitalized) to Stop")
        return alert.runModal() == .alertFirstButtonReturn
            ? .stopAndInstall
            : .waitForTunnels
    }
}

@MainActor
final class UpdateRelaunchGate {
    private let activeTunnelCount: () -> Int
    private let tunnelsHaveStopped: () -> Bool
    private let stopAllTunnels: () -> Void
    private let prompt: any UpdateInstallPrompting
    private let deferredStateDidChange: (Int?) -> Void
    private var deferredInstallHandler: (() -> Void)?
    private var deferredTunnelCount: Int?

    init(
        activeTunnelCount: @escaping () -> Int,
        tunnelsHaveStopped: (() -> Bool)? = nil,
        stopAllTunnels: @escaping () -> Void,
        prompt: any UpdateInstallPrompting = SystemUpdateInstallPrompt(),
        deferredStateDidChange: @escaping (Int?) -> Void = { _ in }
    ) {
        self.activeTunnelCount = activeTunnelCount
        self.tunnelsHaveStopped = tunnelsHaveStopped
            ?? { activeTunnelCount() == 0 }
        self.stopAllTunnels = stopAllTunnels
        self.prompt = prompt
        self.deferredStateDidChange = deferredStateDidChange
    }

    func shouldPostpone(installHandler: @escaping () -> Void) -> Bool {
        let count = activeTunnelCount()
        guard count > 0 else { return false }

        deferredInstallHandler = installHandler
        deferredTunnelCount = count
        deferredStateDidChange(count)
        if prompt.decision(activeTunnelCount: count) == .stopAndInstall {
            stopAllTunnels()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.installDeferredUpdateIfReady()
            }
        }
        return true
    }

    func installDeferredUpdateIfReady() {
        guard let deferredInstallHandler else { return }
        let count = activeTunnelCount()
        guard tunnelsHaveStopped() else {
            if count > 0 {
                deferredTunnelCount = count
            }
            deferredStateDidChange(deferredTunnelCount)
            return
        }
        self.deferredInstallHandler = nil
        deferredTunnelCount = nil
        deferredStateDidChange(nil)
        deferredInstallHandler()
    }

    func prepareForApplicationTermination() -> Bool {
        guard deferredInstallHandler != nil else { return false }
        stopAllTunnels()
        installDeferredUpdateIfReady()
        return true
    }
}

@MainActor
enum UpdateServiceFactory {
    static let shared: any UpdateServicing = {
        #if canImport(Sparkle)
        SparkleUpdateService()
        #else
        UnavailableUpdateService()
        #endif
    }()
}

@MainActor
final class UpdateModel: ObservableObject {
    @Published private(set) var state: UpdateCheckState = .idle
    @Published private(set) var isAvailable = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var canCheckForUpdates = false

    private let service: any UpdateServicing
    private let announcer: any AccessibilityAnnouncing
    private var suppressInlineResultForCurrentCheck = false

    init(
        service: any UpdateServicing,
        announcer: any AccessibilityAnnouncing = SystemAccessibilityAnnouncer()
    ) {
        self.service = service
        self.announcer = announcer
        service.stateDidChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        isAvailable = service.isAvailable
        automaticallyChecksForUpdates = service.automaticallyChecksForUpdates
        if let count = service.deferredInstallTunnelCount {
            state = .waitingForTunnels(count)
        } else if case .waitingForTunnels = state {
            state = .idle
        }
        canCheckForUpdates = service.isAvailable
            && service.canCheckForUpdates
            && service.deferredInstallTunnelCount == nil
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard service.isAvailable else { return }
        service.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func checkForUpdates() {
        refresh()
        guard canCheckForUpdates, state != .checking else { return }

        state = .checking
        suppressInlineResultForCurrentCheck = false
        canCheckForUpdates = false
        announcer.announce("Checking for updates")
        service.checkForUpdates { [weak self] result in
            guard let self else { return }
            let suppressInlineResult = suppressInlineResultForCurrentCheck
            suppressInlineResultForCurrentCheck = false
            switch result {
            case .available:
                state = .idle
                announcer.announce("Update available")
            case .upToDate:
                state = suppressInlineResult ? .idle : .upToDate
                if !suppressInlineResult {
                    announcer.announce("RelayBar is up to date")
                }
            case .failed:
                state = suppressInlineResult ? .idle : .failed
                if !suppressInlineResult {
                    announcer.announce("RelayBar couldn't check for updates")
                }
            }
            refresh()
        }
    }

    func cancelTransientState() {
        if state == .checking {
            suppressInlineResultForCurrentCheck = true
        }
        if case .waitingForTunnels = state {
            return
        }
        state = .idle
    }
}

#if canImport(Sparkle)
@MainActor
private final class SparkleUpdateService: NSObject, UpdateServicing, SPUUpdaterDelegate {
    private let maintainerFeedWasRequested: Bool
    private let maintainerFeedURLString: String?
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var hasStarted = false
    private var checkCompletion: (@MainActor (UpdateCheckResult) -> Void)?
    private var checkResult: UpdateCheckResult?
    private(set) var deferredInstallTunnelCount: Int?
    var stateDidChange: (@MainActor () -> Void)?
    private lazy var relaunchGate = UpdateRelaunchGate(
        activeTunnelCount: { TunnelStore.shared.runningCount },
        tunnelsHaveStopped: {
            TunnelStore.shared.runningCount == 0
                && TunnelStore.shared.terminatingSSHProcessCount == 0
        },
        stopAllTunnels: { TunnelStore.shared.stopAll() },
        deferredStateDidChange: { [weak self] count in
            self?.deferredInstallTunnelCount = count
            self?.stateDidChange?()
        }
    )
    private var tunnelObservation: AnyCancellable?

    override init() {
        let arguments = ProcessInfo.processInfo.arguments
        maintainerFeedWasRequested = MaintainerUpdateFeed.wasRequested(
            arguments: arguments
        )
        maintainerFeedURLString = MaintainerUpdateFeed.urlString(
            arguments: arguments
        )
        super.init()
        tunnelObservation = TunnelStore.shared.$phases
            .combineLatest(TunnelStore.shared.$terminatingSSHProcessCount)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.relaunchGate.installDeferredUpdateIfReady()
                }
            }
    }

    var isAvailable: Bool { true }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.resetUpdateCycle()
        }
    }

    var canCheckForUpdates: Bool {
        hasStarted && controller.updater.canCheckForUpdates
    }

    func start() {
        guard !hasStarted else { return }
        guard !maintainerFeedWasRequested || maintainerFeedURLString != nil else {
            NSLog("RelayBar rejected an invalid maintainer update feed launch argument.")
            return
        }
        do {
            try controller.updater.start()
            hasStarted = true
        } catch {
            NSLog("RelayBar updater could not start: %@", error.localizedDescription)
        }
    }

    func checkForUpdates(
        completion: @escaping @MainActor (UpdateCheckResult) -> Void
    ) {
        guard canCheckForUpdates, checkCompletion == nil else {
            completion(.failed)
            return
        }
        checkCompletion = completion
        checkResult = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func prepareForApplicationTermination() -> Bool {
        relaunchGate.prepareForApplicationTermination()
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        maintainerFeedURLString
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        finishCheckEarly(with: .available)
    }

    func updaterDidNotFindUpdate(
        _ updater: SPUUpdater,
        error: Error
    ) {
        guard checkCompletion != nil else { return }
        // Sparkle's stable SPUNoUpdateFoundReason raw values: latest (1) and
        // newer-than-feed (2) are truthful "up to date" outcomes. OS or
        // hardware incompatibility must remain a retryable failure instead.
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?
            .intValue
        finishCheckEarly(
            with: reason == 1 || reason == 2 ? .upToDate : .failed
        )
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard let completion = checkCompletion else {
            if checkResult != nil {
                checkResult = nil
                return
            }
            if let error {
                NSLog("RelayBar scheduled update check ended: %@", error.localizedDescription)
            }
            return
        }

        checkCompletion = nil
        let result: UpdateCheckResult
        if let checkResult {
            result = checkResult
        } else {
            result = .failed
        }
        self.checkResult = nil
        completion(result)
    }

    private func finishCheckEarly(with result: UpdateCheckResult) {
        guard let completion = checkCompletion else { return }
        checkCompletion = nil
        checkResult = result
        completion(result)
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        relaunchGate.shouldPostpone(installHandler: installHandler)
    }
}
#endif
