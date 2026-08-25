import Foundation
import RelayBarCore

/// Loads and saves the Linux profile file: a plain JSON array of the same
/// `Tunnel` records the macOS app persists, so profiles can be carried over
/// by copying their JSON.
final class ProfileStore {
    private let fileURL: URL
    private let encoder: JSONEncoder = .init()
    private let decoder: JSONDecoder = .init()

    /// - Parameter fileURL: defaults to `$XDG_CONFIG_HOME/relaybar/tunnels.json`.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() -> [Tunnel] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let tunnels = try decoder.decode([Tunnel].self, from: data)
            // Unsafe or duplicated-listener profiles never reach the menu;
            // the macOS app applies the same gate before showing controls.
            return tunnels.filter(\.isSafeToRun)
        } catch {
            FileHandle.standardError.write(
                Data("relaybar-tray: ignoring unreadable profiles: \(error)\n".utf8)
            )
            return []
        }
    }

    func save(_ tunnels: [Tunnel]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(tunnels)
        // Atomic replace so a crash mid-write cannot truncate the profile file.
        let temporaryURL = directory.appendingPathComponent(
            ".tunnels.json.tmp-\(UUID().uuidString)"
        )
        try data.write(to: temporaryURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
    }

    static func defaultFileURL() -> URL {
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        return configHome
            .appendingPathComponent("relaybar", isDirectory: true)
            .appendingPathComponent("tunnels.json")
    }
}
