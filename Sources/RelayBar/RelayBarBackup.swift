import CryptoKit
import Foundation

enum BackupImportMode: Equatable, Sendable {
    /// Adds only what is not saved yet and leaves everything saved unchanged.
    case addMissing
    /// Makes the saved profiles and Remote Files hosts exactly the backup's.
    case replaceAll
}

/// A standalone Remote Files host as a backup carries it.
struct BackupRemoteFilesHost: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sshHost: String
    let additionalArguments: [String]

    var connectionIdentity: RemoteServer.ConnectionIdentity {
        RemoteServer.ConnectionIdentity(
            sshHost: sshHost,
            additionalArguments: additionalArguments
        )
    }
}

/// The work a backup preserves: forwarding profiles and standalone Remote
/// Files hosts. Recent connections and locations, window and menu sizes,
/// and system state such as Launch at Login are deliberately absent; they
/// are history or device state rather than something the user built.
struct RelayBarBackupContents: Equatable, Sendable {
    var profiles: [Tunnel]
    var remoteFilesHosts: [BackupRemoteFilesHost]

    var isEmpty: Bool {
        profiles.isEmpty && remoteFilesHosts.isEmpty
    }
}

struct BackupImportResult: Equatable, Sendable {
    let profileCount: Int
    let remoteFilesHostCount: Int
}

/// What an import would change, counted before the user decides.
struct BackupImportPreview: Equatable, Sendable {
    let profileCount: Int
    let remoteFilesHostCount: Int
    let missingProfileCount: Int
    let missingRemoteFilesHostCount: Int

    init(
        importing backup: RelayBarBackupContents,
        into current: RelayBarBackupContents
    ) {
        let savedProfileIDs = Set(current.profiles.map(\.id))
        let savedConnections = Set(
            current.remoteFilesHosts.map(\.connectionIdentity)
        )
        profileCount = backup.profiles.count
        remoteFilesHostCount = backup.remoteFilesHosts.count
        missingProfileCount = backup.profiles.filter {
            !savedProfileIDs.contains($0.id)
        }.count
        missingRemoteFilesHostCount = backup.remoteFilesHosts.filter {
            !savedConnections.contains($0.connectionIdentity)
        }.count
    }

    var hasMissingItems: Bool {
        missingProfileCount > 0 || missingRemoteFilesHostCount > 0
    }
}

enum RelayBarBackupError: LocalizedError, Equatable {
    case tooLarge
    case notABackup
    case newerVersion
    case damaged(String)
    case unreadable(String)
    case folderMissing(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "The file is larger than a RelayBar backup can be."
        case .notABackup:
            return "The file isn't a RelayBar backup."
        case .newerVersion:
            return "The backup was made by a newer version of RelayBar. Update RelayBar to import it."
        case .damaged(let detail):
            return "The backup is damaged. \(detail)"
        case .unreadable(let detail):
            return detail
        case .folderMissing(let name):
            return "The backup folder \u{201c}\(name)\u{201d} can't be found. Choose it again or pick another folder."
        }
    }
}

/// The backup file format: one pretty-printed JSON document that a person
/// can read and that a later version can recognize.
///
/// ```json
/// {
///   "createdAt" : "2026-09-29T10:00:05Z",
///   "format" : "com.relaybarscion.backup",
///   "profiles" : [ … the same records as savedTunnels.v2 … ],
///   "remoteFilesHosts" : [ { "id", "name", "sshHost", "additionalArguments" } ],
///   "version" : 1
/// }
/// ```
enum RelayBarBackupCodec {
    static let formatIdentifier = "com.relaybarscion.backup"
    static let currentVersion = 1
    /// Far above any real profile list, low enough that a wrong pick in the
    /// open panel is refused before it is read into memory.
    static let maximumFileSize = 4 * 1_024 * 1_024
    static let maximumRemoteFilesHostCount = 128

    private struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    private struct Document: Codable {
        let format: String
        let version: Int
        let createdAt: Date?
        let profiles: [Tunnel]
        let remoteFilesHosts: [BackupRemoteFilesHost]
    }

    static func encode(
        _ contents: RelayBarBackupContents,
        createdAt: Date
    ) throws -> Data {
        try makeEncoder().encode(document(for: contents, createdAt: createdAt))
    }

    /// Identifies the contents independently of when they were written, so
    /// automatic backups are written only when something actually changed.
    static func digest(of contents: RelayBarBackupContents) throws -> String {
        let data = try makeEncoder().encode(document(for: contents, createdAt: nil))
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Profiles decode through the same rules as saved profiles, so a backup
    /// cannot carry anything the saved list would not load. Hosts must pass
    /// the saved-host rules; repeated hosts collapse to their first entry.
    static func decode(_ data: Data) throws -> RelayBarBackupContents {
        guard data.count <= maximumFileSize else {
            throw RelayBarBackupError.tooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let header = try? decoder.decode(Header.self, from: data),
            header.format == formatIdentifier,
            let version = header.version,
            version >= 1
        else {
            throw RelayBarBackupError.notABackup
        }
        guard version <= currentVersion else {
            throw RelayBarBackupError.newerVersion
        }

        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw RelayBarBackupError.damaged(damageDescription(for: error))
        }

        guard Set(document.profiles.map(\.id)).count == document.profiles.count else {
            throw RelayBarBackupError.damaged(
                "It lists the same profile more than once."
            )
        }

        var hosts: [BackupRemoteFilesHost] = []
        var seenConnections: Set<RemoteServer.ConnectionIdentity> = []
        var seenIDs: Set<UUID> = []
        for host in document.remoteFilesHosts {
            guard
                RemoteServerCatalog.isValidSavedHost(
                    name: host.name,
                    sshHost: host.sshHost,
                    additionalArguments: host.additionalArguments
                )
            else {
                throw RelayBarBackupError.damaged(
                    "The Remote Files host \u{201c}\(host.name)\u{201d} isn't valid."
                )
            }
            guard
                seenConnections.insert(host.connectionIdentity).inserted,
                seenIDs.insert(host.id).inserted
            else {
                continue
            }
            hosts.append(host)
        }
        guard hosts.count <= maximumRemoteFilesHostCount else {
            throw RelayBarBackupError.damaged(
                "It lists more than \(maximumRemoteFilesHostCount) Remote Files hosts."
            )
        }

        return RelayBarBackupContents(
            profiles: document.profiles,
            remoteFilesHosts: hosts
        )
    }

    private static func document(
        for contents: RelayBarBackupContents,
        createdAt: Date?
    ) -> Document {
        Document(
            format: formatIdentifier,
            version: currentVersion,
            createdAt: createdAt,
            profiles: contents.profiles,
            remoteFilesHosts: contents.remoteFilesHosts
        )
    }

    /// Sorted keys make equal contents encode to equal bytes, which the
    /// digest relies on, and keep diffs between backups readable.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func damageDescription(for error: Error) -> String {
        // `if case` rather than `switch`: DecodingError is not frozen, and
        // only these two cases carry text worth showing.
        if case .dataCorrupted(let context) = error as? DecodingError {
            return context.debugDescription
        }
        if case .keyNotFound(let key, _) = error as? DecodingError {
            return "The value \u{201c}\(key.stringValue)\u{201d} is missing."
        }
        return "A value has the wrong type or is missing."
    }
}

/// Names for backup files. Automatic backups carry a to-the-second local
/// timestamp, so their names sort chronologically and retention can find
/// them without touching anything else in the folder. Exports use a
/// different prefix, so an export saved into the backup folder is never
/// mistaken for an automatic backup and pruned.
enum BackupFileNaming {
    static let automaticPrefix = "RelayBar Backup "
    static let exportPrefix = "RelayBar Export "
    static let pathExtension = "json"
    static let retainedAutomaticBackupCount = 30

    private static let automaticPattern =
        #"^RelayBar Backup [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{6}\.json$"#

    static func automaticBackupName(
        for date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let parts = components(of: date, in: timeZone)
        return automaticPrefix
            + String(
                format: "%04ld-%02ld-%02ld %02ld%02ld%02ld",
                parts.year ?? 0,
                parts.month ?? 0,
                parts.day ?? 0,
                parts.hour ?? 0,
                parts.minute ?? 0,
                parts.second ?? 0
            )
            + ".\(pathExtension)"
    }

    static func exportName(for date: Date, timeZone: TimeZone = .current) -> String {
        let parts = components(of: date, in: timeZone)
        return exportPrefix
            + String(
                format: "%04ld-%02ld-%02ld",
                parts.year ?? 0,
                parts.month ?? 0,
                parts.day ?? 0
            )
            + ".\(pathExtension)"
    }

    static func isAutomaticBackupName(_ name: String) -> Bool {
        name.range(of: automaticPattern, options: .regularExpression) != nil
    }

    /// The automatic backups beyond the newest `count`, oldest first. Names
    /// sort chronologically except across the repeated hour when daylight
    /// saving time ends, which can only change which of the oldest copies
    /// goes first.
    static func automaticBackupNamesToPrune(
        _ names: [String],
        keeping count: Int
    ) -> [String] {
        let backups = names.filter(isAutomaticBackupName).sorted()
        return Array(backups.dropLast(max(0, count)))
    }

    private static func components(
        of date: Date,
        in timeZone: TimeZone
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}

/// File-system work for backups, kept apart from the model so its rules are
/// explicit: never create a missing backup folder (it may be an unmounted
/// volume), and only ever delete regular files named as automatic backups.
struct BackupFiles {
    let fileManager: FileManager

    func requireFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw RelayBarBackupError.folderMissing(folder.lastPathComponent)
        }
    }

    /// Writes atomically, then restricts the file to its owner: a backup
    /// lists hosts, accounts, and forwarded services.
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            // The backup itself exists; a volume that cannot store POSIX
            // permissions must not turn it into a reported failure.
            NSLog(
                "RelayBar Scion could not restrict permissions on %@: %@",
                url.path,
                error.localizedDescription
            )
        }
    }

    func read(_ url: URL) throws -> Data {
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw RelayBarBackupError.unreadable(error.localizedDescription)
        }
        guard (size ?? 0) <= RelayBarBackupCodec.maximumFileSize else {
            throw RelayBarBackupError.tooLarge
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw RelayBarBackupError.unreadable(error.localizedDescription)
        }
    }

    /// Best effort: a copy that cannot be removed now is removed by a later
    /// backup, and never blocks the backup that was just written.
    func pruneAutomaticBackups(in folder: URL, keeping count: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys
            )
        else {
            return
        }
        let backups = entries.filter { entry in
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
        let namesToPrune = Set(
            BackupFileNaming.automaticBackupNamesToPrune(
                backups.map(\.lastPathComponent),
                keeping: count
            )
        )
        for entry in backups where namesToPrune.contains(entry.lastPathComponent) {
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                NSLog(
                    "RelayBar Scion could not remove the old backup %@: %@",
                    entry.path,
                    error.localizedDescription
                )
            }
        }
    }
}

/// User-facing backup copy, kept pure so pluralization stays testable away
/// from panels and alerts.
enum BackupCopy {
    static let addMissingButtonTitle = "Add Missing"
    static let replaceAllButtonTitle = "Replace All"
    static let cancelButtonTitle = "Cancel"

    static func summary(profileCount: Int, remoteFilesHostCount: Int) -> String {
        "\(count(profileCount, "profile", "profiles")) and "
            + count(remoteFilesHostCount, "Remote Files host", "Remote Files hosts")
    }

    static func importMessageText(fileName: String) -> String {
        "Import \u{201c}\(fileName)\u{201d}?"
    }

    static func importInformativeText(for preview: BackupImportPreview) -> String {
        let contents = "This backup has "
            + summary(
                profileCount: preview.profileCount,
                remoteFilesHostCount: preview.remoteFilesHostCount
            )
        let replaceAll = "Replace All removes every saved profile and Remote Files host "
            + "that isn't in the backup, restores the backup's version of the rest, "
            + "and stops any active tunnels."
        guard preview.hasMissingItems else {
            return "\(contents), and you already have all of them.\n\n\(replaceAll)"
        }
        let missing = summary(
            profileCount: preview.missingProfileCount,
            remoteFilesHostCount: preview.missingRemoteFilesHostCount
        )
        return "\(contents). \(missing) aren't in RelayBar yet.\n\n"
            + "Add Missing adds only those and leaves everything you have unchanged. "
            + replaceAll
    }

    static func importResultText(
        _ result: BackupImportResult,
        mode: BackupImportMode
    ) -> String {
        let changed = summary(
            profileCount: result.profileCount,
            remoteFilesHostCount: result.remoteFilesHostCount
        )
        switch mode {
        case .addMissing:
            return "Added \(changed)."
        case .replaceAll:
            return "Restored \(changed) from the backup."
        }
    }

    static func exportResultText(for contents: RelayBarBackupContents) -> String {
        "Exported "
            + summary(
                profileCount: contents.profiles.count,
                remoteFilesHostCount: contents.remoteFilesHosts.count
            )
            + "."
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural)"
    }
}
