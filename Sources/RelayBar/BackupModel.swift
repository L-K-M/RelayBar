import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Where backups read the saved work from and write an import back to.
@MainActor
protocol BackupDataSource: AnyObject {
    func currentBackupContents() -> RelayBarBackupContents
    func importBackupContents(
        _ contents: RelayBarBackupContents,
        mode: BackupImportMode
    ) -> BackupImportResult
}

/// The app's saved work: the tunnel store's profiles and the one
/// app-lifetime Remote Files catalog, so an import can never be overwritten
/// by a stale in-memory copy of the saved hosts.
@MainActor
final class StoreBackupDataSource: BackupDataSource {
    private let store: TunnelStore
    private let catalog: RemoteServerCatalog
    private let savedHostsDidChange: @MainActor () -> Void

    init(
        store: TunnelStore,
        catalog: RemoteServerCatalog,
        savedHostsDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.catalog = catalog
        self.savedHostsDidChange = savedHostsDidChange
    }

    func currentBackupContents() -> RelayBarBackupContents {
        RelayBarBackupContents(
            profiles: store.tunnels,
            remoteFilesHosts: catalog.savedHostsForBackup
        )
    }

    func importBackupContents(
        _ contents: RelayBarBackupContents,
        mode: BackupImportMode
    ) -> BackupImportResult {
        let profileCount = store.importProfiles(contents.profiles, mode: mode)
        let hostCount = catalog.importSavedHosts(contents.remoteFilesHosts, mode: mode)
        savedHostsDidChange()
        return BackupImportResult(
            profileCount: profileCount,
            remoteFilesHostCount: hostCount
        )
    }
}

/// The panels and alert backups need. The app supplies AppKit; tests supply
/// scripted answers.
@MainActor
protocol BackupPanelPresenting: AnyObject {
    func chooseBackupFolder(current: URL?) -> URL?
    func chooseExportDestination(suggestedName: String) -> URL?
    func chooseImportFile() -> URL?
    /// Returns the chosen import mode, or `nil` when the user cancels.
    func confirmImport(_ preview: BackupImportPreview, fileName: String) -> BackupImportMode?
}

@MainActor
final class AppKitBackupPanelPresenter: BackupPanelPresenting {
    func chooseBackupFolder(current: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Backup Folder"
        panel.message = "RelayBar saves a backup in this folder after each change."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func chooseExportDestination(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.prompt = "Export"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Backup"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.allowsMultipleSelection = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func confirmImport(_ preview: BackupImportPreview, fileName: String) -> BackupImportMode? {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = BackupCopy.importMessageText(fileName: fileName)
        alert.informativeText = BackupCopy.importInformativeText(for: preview)

        // Buttons in order, so the response maps back to a mode by index.
        var modes: [BackupImportMode] = []
        if preview.hasMissingItems {
            alert.addButton(withTitle: BackupCopy.addMissingButtonTitle)
            modes.append(.addMissing)
        }
        let replaceButton = alert.addButton(withTitle: BackupCopy.replaceAllButtonTitle)
        // Replace All deletes saved work and stops tunnels; say so in red.
        replaceButton.hasDestructiveAction = true
        modes.append(.replaceAll)
        alert.addButton(withTitle: BackupCopy.cancelButtonTitle)

        let index = alert.runModal().rawValue
            - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard modes.indices.contains(index) else { return nil }
        return modes[index]
    }
}

/// Owns backup settings and actions for the Settings screen: automatic
/// backups into a user-chosen folder, and explicit export and import.
///
/// Automatic backups watch `UserDefaults` rather than each store: saved
/// profiles and Remote Files hosts both persist there, so one in-process
/// change notification covers every route that edits either, including
/// ones added later. Each notification only schedules a check; a backup is
/// written after changes settle, and only when the contents' digest differs
/// from the last backup written.
@MainActor
final class BackupModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case succeeded(String)
        case failed(String)
    }

    enum AutomaticBackupOutcome: Equatable {
        /// Off, no folder, nothing saved, or nothing changed since the last one.
        case notNeeded
        case written
        case failed(String)
    }

    enum StorageKey {
        static let automaticBackupsEnabled = "backup.automatic.enabled.v1"
        static let folderPath = "backup.folderPath.v1"
        static let lastAutomaticDigest = "backup.automatic.lastDigest.v1"
        static let lastAutomaticDate = "backup.automatic.lastDate.v1"
    }

    @Published private(set) var isAutomaticBackupEnabled: Bool
    @Published private(set) var folder: URL?
    @Published private(set) var lastAutomaticBackupDate: Date?
    @Published private(set) var automaticBackupError: String?
    /// The latest export or import outcome, cleared when Settings closes.
    @Published private(set) var activity: Activity = .idle

    private let dataSource: any BackupDataSource
    private let presenter: any BackupPanelPresenting
    private let defaults: UserDefaults
    private let files: BackupFiles
    private let now: () -> Date
    private let settleDelay: TimeInterval
    private var pendingBackupTask: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?

    init(
        dataSource: any BackupDataSource,
        presenter: (any BackupPanelPresenting)? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() },
        settleDelay: TimeInterval = 2
    ) {
        self.dataSource = dataSource
        // Resolved in the body: a default argument would construct a
        // MainActor-isolated presenter from a nonisolated context.
        self.presenter = presenter ?? AppKitBackupPanelPresenter()
        self.defaults = defaults
        files = BackupFiles(fileManager: fileManager)
        self.now = now
        self.settleDelay = max(0, settleDelay)

        let folder = defaults.string(forKey: StorageKey.folderPath).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        self.folder = folder
        isAutomaticBackupEnabled = folder != nil
            && defaults.bool(forKey: StorageKey.automaticBackupsEnabled)
        lastAutomaticBackupDate = defaults.object(
            forKey: StorageKey.lastAutomaticDate
        ) as? Date
    }

    var folderDisplayPath: String? {
        folder.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    /// Starts watching for saved-data changes and backs up once now, so a
    /// change made while RelayBar was not running is still captured.
    func startAutomaticBackups() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleAutomaticBackup()
                }
            }
        performAutomaticBackupIfNeeded()
    }

    /// Turning backups on without a folder asks for one first; cancelling
    /// that leaves backups off.
    func setAutomaticBackupEnabled(_ enabled: Bool) {
        guard enabled else {
            pendingBackupTask?.cancel()
            pendingBackupTask = nil
            isAutomaticBackupEnabled = false
            automaticBackupError = nil
            defaults.set(false, forKey: StorageKey.automaticBackupsEnabled)
            return
        }

        if folder == nil {
            guard let chosen = presenter.chooseBackupFolder(current: nil) else { return }
            setFolder(chosen)
        }
        isAutomaticBackupEnabled = true
        defaults.set(true, forKey: StorageKey.automaticBackupsEnabled)
        backUpAfterSettingsChange()
    }

    func chooseFolder() {
        guard let chosen = presenter.chooseBackupFolder(current: folder) else { return }
        setFolder(chosen)
        backUpAfterSettingsChange()
    }

    /// Writes a backup when automatic backups are on and the contents
    /// differ from the last one written. An empty profile and host list is
    /// never backed up, so clearing everything cannot push the last useful
    /// copies out of the folder. Also called before an import and at quit,
    /// so neither can outrun the backup of what it replaces.
    @discardableResult
    func performAutomaticBackupIfNeeded() -> AutomaticBackupOutcome {
        pendingBackupTask?.cancel()
        pendingBackupTask = nil
        guard isAutomaticBackupEnabled, let folder else { return .notNeeded }

        let contents = dataSource.currentBackupContents()
        guard !contents.isEmpty else { return .notNeeded }

        let date = now()
        let digest: String
        do {
            digest = try RelayBarBackupCodec.digest(of: contents)
            guard digest != defaults.string(forKey: StorageKey.lastAutomaticDigest) else {
                return .notNeeded
            }
            try files.requireFolder(folder)
            let data = try RelayBarBackupCodec.encode(contents, createdAt: date)
            try files.write(
                data,
                to: folder.appendingPathComponent(
                    BackupFileNaming.automaticBackupName(for: date)
                )
            )
        } catch {
            // The digest stays unrecorded, so the next change or launch
            // tries again.
            let message = Self.message(for: error)
            automaticBackupError = message
            return .failed(message)
        }

        files.pruneAutomaticBackups(
            in: folder,
            keeping: BackupFileNaming.retainedAutomaticBackupCount
        )
        defaults.set(digest, forKey: StorageKey.lastAutomaticDigest)
        defaults.set(date, forKey: StorageKey.lastAutomaticDate)
        lastAutomaticBackupDate = date
        automaticBackupError = nil
        return .written
    }

    /// An empty export is refused before the save panel opens: it would
    /// preserve nothing, and importing it with Replace All would erase
    /// everything.
    func exportBackup() {
        let contents = dataSource.currentBackupContents()
        guard !contents.isEmpty else {
            activity = .failed(
                "There's nothing to export yet. Add a profile or a Remote Files host first."
            )
            return
        }

        let date = now()
        guard
            let destination = presenter.chooseExportDestination(
                suggestedName: BackupFileNaming.exportName(for: date)
            )
        else {
            return
        }

        do {
            let data = try RelayBarBackupCodec.encode(contents, createdAt: date)
            try files.write(data, to: destination)
        } catch {
            activity = .failed("Couldn't export. \(Self.message(for: error))")
            return
        }
        activity = .succeeded(BackupCopy.exportResultText(for: contents))
    }

    func importBackup() {
        guard let source = presenter.chooseImportFile() else { return }

        let contents: RelayBarBackupContents
        do {
            contents = try RelayBarBackupCodec.decode(files.read(source))
        } catch {
            activity = .failed(
                "Couldn't import \u{201c}\(source.lastPathComponent)\u{201d}. "
                    + Self.message(for: error)
            )
            return
        }

        let preview = BackupImportPreview(
            importing: contents,
            into: dataSource.currentBackupContents()
        )
        guard
            let mode = presenter.confirmImport(
                preview,
                fileName: source.lastPathComponent
            )
        else {
            return
        }

        // Replace All deletes saved work, so it never runs past a failed
        // backup of that work. Add Missing changes nothing saved and may
        // proceed.
        if
            case .failed(let reason) = performAutomaticBackupIfNeeded(),
            mode == .replaceAll
        {
            activity = .failed(
                "Nothing was replaced, because RelayBar couldn't back up "
                    + "your current profiles first. \(reason)"
            )
            return
        }
        let result = dataSource.importBackupContents(contents, mode: mode)
        activity = .succeeded(BackupCopy.importResultText(result, mode: mode))
    }

    func cancelTransientState() {
        activity = .idle
    }

    private func setFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        folder = standardized
        automaticBackupError = nil
        defaults.set(standardized.path, forKey: StorageKey.folderPath)
    }

    /// A new folder, or backups turned back on, gets a fresh backup now
    /// rather than at the next edit, which also proves the folder works.
    private func backUpAfterSettingsChange() {
        defaults.removeObject(forKey: StorageKey.lastAutomaticDigest)
        performAutomaticBackupIfNeeded()
    }

    private func scheduleAutomaticBackup() {
        guard isAutomaticBackupEnabled else { return }
        pendingBackupTask?.cancel()
        let delay = settleDelay
        pendingBackupTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.performAutomaticBackupIfNeeded()
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
