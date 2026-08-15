import AppKit
import Foundation
import ImageIO

@MainActor
protocol RemoteFilePresenting: AnyObject {
    func chooseDestination(for entry: RemoteFileEntry) -> URL?
    func revealInFinder(_ destination: URL)
}

@MainActor
final class AppKitRemoteFilePresenter: RemoteFilePresenting {
    func chooseDestination(for entry: RemoteFileEntry) -> URL? {
        if entry.isDirectory {
            let panel = NSOpenPanel()
            panel.title = "Choose where to download \(entry.name)"
            panel.prompt = "Choose"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let parent = panel.url else { return nil }

            let destination = parent.appendingPathComponent(entry.name, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                let alert = NSAlert()
                alert.messageText = "Replace “\(entry.name)”?"
                alert.informativeText =
                    "RelayBar will keep the existing folder until the new download finishes."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            }
            return destination
        }

        let panel = NSSavePanel()
        panel.title = "Download \(entry.name)"
        panel.prompt = "Download"
        panel.nameFieldStringValue = entry.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func revealInFinder(_ destination: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}

enum RemoteImageDecoder {
    private static let maximumSourceDimension = 100_000
    private static let maximumSourcePixels = 100_000_000
    private static let thumbnailDimension = 4_096

    static func decode(contentsOf url: URL) throws -> NSImage {
        let image = try decodeCGImage(contentsOf: url)
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    static func decodeCGImage(contentsOf url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0
        else {
            throw RemoteFileError.unsupportedImage
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard
            !pixelCount.overflow,
            width <= maximumSourceDimension,
            height <= maximumSourceDimension,
            pixelCount.partialValue <= maximumSourcePixels
        else {
            throw RemoteFileError.imageDimensionsTooLarge
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        else {
            throw RemoteFileError.unsupportedImage
        }
        return image
    }
}

/// Core Graphics images are immutable but do not carry Sendable annotations.
private struct DecodedRemoteImage: @unchecked Sendable {
    let value: CGImage
}

struct RemoteDirectoryCache {
    struct Key: Hashable {
        let connection: RemoteServer.ConnectionIdentity
        let path: String
    }

    private struct Snapshot {
        let entries: [RemoteFileEntry]
        let cost: Int
        var lastAccess: UInt64
    }

    let maximumEntryCount: Int
    private var snapshots: [Key: Snapshot] = [:]
    private(set) var entryCount = 0
    private var accessSequence: UInt64 = 0

    init(maximumEntryCount: Int = 20_000) {
        self.maximumEntryCount = maximumEntryCount
    }

    mutating func entries(
        for connection: RemoteServer.ConnectionIdentity,
        path: String
    ) -> [RemoteFileEntry]? {
        let key = Key(connection: connection, path: RemotePath.normalized(path))
        guard var snapshot = snapshots[key] else { return nil }
        accessSequence &+= 1
        snapshot.lastAccess = accessSequence
        snapshots[key] = snapshot
        return snapshot.entries
    }

    mutating func insert(
        _ entries: [RemoteFileEntry],
        for connection: RemoteServer.ConnectionIdentity,
        path: String
    ) {
        let key = Key(connection: connection, path: RemotePath.normalized(path))
        if let existing = snapshots.removeValue(forKey: key) {
            entryCount -= existing.cost
        }
        // Empty folders still consume cache metadata, so charge one unit and
        // keep the cache bounded even when every snapshot is empty.
        let cost = max(entries.count, 1)
        guard cost <= maximumEntryCount else { return }

        accessSequence &+= 1
        snapshots[key] = Snapshot(
            entries: entries,
            cost: cost,
            lastAccess: accessSequence
        )
        entryCount += cost

        while entryCount > maximumEntryCount {
            guard
                let oldest = snapshots.min(by: {
                    $0.value.lastAccess < $1.value.lastAccess
                })
            else {
                break
            }
            snapshots.removeValue(forKey: oldest.key)
            entryCount -= oldest.value.cost
        }
    }

    func contains(
        connection: RemoteServer.ConnectionIdentity,
        path: String
    ) -> Bool {
        snapshots[Key(connection: connection, path: RemotePath.normalized(path))] != nil
    }

    mutating func removeAll() {
        snapshots.removeAll()
        entryCount = 0
        accessSequence = 0
    }
}

@MainActor
final class RemoteFilesModel: ObservableObject {
    enum Screen: Equatable {
        case launcher
        case browser
        case preview
    }

    struct TransferPresentation: Identifiable {
        enum Phase: Equatable {
            case active
            case cancelling
            case completed
            case failed
            case cancelled
        }

        let id = UUID()
        let entry: RemoteFileEntry
        let destination: URL
        var completedBytes: Int64
        let totalBytes: Int64?
        var phase: Phase
        var message: String?

        var fraction: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
        }
    }

    @Published private(set) var screen: Screen = .launcher
    @Published private(set) var servers: [RemoteServer]
    @Published var selectedServerID: UUID? {
        didSet {
            // Offer the selected server's last opened path in an untouched
            // launcher field; never clobber text the user typed.
            guard screen == .launcher, remotePath.isEmpty else { return }
            prefillLastPathForSelectedServer()
        }
    }
    @Published var remotePath = ""
    @Published private(set) var currentPath = ""
    @Published private(set) var pendingPath: String?
    @Published private(set) var entries: [RemoteFileEntry] = []
    @Published var selectedEntryID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewEntry: RemoteFileEntry?
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var previewMarkdown: RemoteMarkdownDocument?
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var transfer: TransferPresentation?

    private let service: RemoteFileServing
    private let presenter: RemoteFilePresenting
    private let serverCatalog: RemoteServerCatalog
    private let imageDecoder: @Sendable (URL) throws -> CGImage
    private let markdownDecoder: (URL) async throws -> RemoteMarkdownDocument
    private var tunnels: [Tunnel]
    private var activeServer: RemoteServer?
    private var navigationHistory: [String] = []
    /// Whether the browser currently shows a directly opened file as the only
    /// entry. In that state Back has no folder history to pop, so it opens
    /// the containing folder instead of abandoning the browser for the
    /// launcher.
    private var showsDirectFile = false
    private var directoryCache = RemoteDirectoryCache()
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var previewURL: URL?
    private var loadGeneration = UUID()
    private var previewGeneration = UUID()
    private var transferGeneration = UUID()
    private var retryLoadRequest: (
        path: String,
        server: RemoteServer,
        previousPath: String?,
        isRefresh: Bool,
        popsHistory: Bool,
        selectionAfterLoad: String?,
        resolvesFile: Bool
    )?

    init(
        tunnels: [Tunnel],
        service: RemoteFileServing = SFTPRemoteFileService(),
        presenter: RemoteFilePresenting? = nil,
        imageDecoder: @escaping @Sendable (URL) throws -> CGImage =
            { try RemoteImageDecoder.decodeCGImage(contentsOf: $0) },
        markdownDecoder: @escaping (URL) async throws -> RemoteMarkdownDocument =
            { try await RemoteMarkdownDecoder.load(contentsOf: $0) },
        serverCatalog: RemoteServerCatalog? = nil
    ) {
        let catalog = serverCatalog ?? RemoteServerCatalog()
        let initialServers = catalog.servers(from: tunnels)
        servers = initialServers
        selectedServerID = initialServers.first?.id
        self.service = service
        self.presenter = presenter ?? AppKitRemoteFilePresenter()
        self.serverCatalog = catalog
        self.imageDecoder = imageDecoder
        self.markdownDecoder = markdownDecoder
        self.tunnels = tunnels
        if let firstServer = initialServers.first {
            remotePath = catalog.lastOpenedPath(for: firstServer) ?? ""
        }
    }

    var pathValidationMessage: String? {
        RemotePath.validationMessage(for: remotePath)
    }

    var canOpen: Bool {
        selectedServer != nil && pathValidationMessage == nil && !isLoading
    }

    var canCancelInitialOpen: Bool {
        // `isLoading` is set on the launcher only by the explicit initial
        // path open; browser loads use the same flag on `.browser`.
        screen == .launcher && isLoading
    }

    var presentedPath: String {
        pendingPath ?? currentPath
    }

    var canGoBack: Bool {
        if screen == .preview {
            return true
        }
        guard screen == .browser, !isTransferRunning else { return false }
        return !isLoading || pendingPath != nil
    }

    var backHelp: String {
        if isLoading, pendingPath != nil {
            return "Cancel opening this folder"
        }
        if isTransferRunning {
            return "Cancel the transfer before closing this folder"
        }
        return "Go back"
    }

    var selectedEntry: RemoteFileEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var previewableEntries: [RemoteFileEntry] {
        entries.filter(\.isPreviewable)
    }

    var selectedServer: RemoteServer? {
        guard let selectedServerID else { return nil }
        return servers.first { $0.id == selectedServerID }
    }

    func updateTunnels(_ tunnels: [Tunnel]) {
        self.tunnels = tunnels
        let selectedConnection = selectedServer?.connectionIdentity
        let updatedServers = serverCatalog.servers(from: tunnels)
        servers = updatedServers

        if
            let selectedConnection,
            let matchingServer = updatedServers.first(where: {
                $0.connectionIdentity == selectedConnection
            })
        {
            selectedServerID = matchingServer.id
        } else if screen == .launcher {
            selectedServerID = updatedServers.first?.id
        }
    }

    func servers(from source: RemoteServer.Source) -> [RemoteServer] {
        servers.filter { $0.source == source }
    }

    var canRemoveSelectedServer: Bool {
        guard let selectedServerID else { return false }
        return serverCatalog.isSavedServer(id: selectedServerID)
    }

    func addServer(name: String, sshHost: String) throws {
        let server = try serverCatalog.add(name: name, sshHost: sshHost)
        refreshServers(preferredConnection: server.connectionIdentity)
    }

    func removeSelectedServer() {
        guard let selectedServerID else { return }
        serverCatalog.removeSavedServer(id: selectedServerID)
        refreshServers(preferredConnection: nil)
    }

    func openRemotePath() {
        guard let server = selectedServer else {
            errorMessage = "Add or select an SSH server before opening remote files."
            return
        }
        guard pathValidationMessage == nil else {
            errorMessage = pathValidationMessage
            return
        }

        if
            let activeServer,
            activeServer.connectionIdentity != server.connectionIdentity
        {
            service.shutdown()
            directoryCache.removeAll()
        }
        navigationHistory = []
        activeServer = server
        load(
            path: RemotePath.normalized(remotePath),
            server: server,
            previousPath: nil,
            resolvesFile: true
        )
    }

    func cancelInitialOpen() {
        guard canCancelInitialOpen else { return }

        loadTask?.cancel()
        loadGeneration = UUID()
        loadTask = nil
        pendingPath = nil
        isLoading = false
        isRefreshing = false
        errorMessage = nil
        retryLoadRequest = nil
        activeServer = nil
        directoryCache.removeAll()
        service.shutdown()
    }

    func refresh() {
        guard
            screen == .browser,
            let server = activeServer,
            !currentPath.isEmpty,
            !isLoading,
            !isRefreshing
        else { return }
        load(path: currentPath, server: server, previousPath: nil, isRefresh: true)
    }

    func retryLastLoad() {
        guard let request = retryLoadRequest else {
            refresh()
            return
        }
        load(
            path: request.path,
            server: request.server,
            previousPath: request.previousPath,
            isRefresh: request.isRefresh,
            popsHistory: request.popsHistory,
            selectionAfterLoad: request.selectionAfterLoad,
            resolvesFile: request.resolvesFile
        )
    }

    func goBack() {
        if screen == .preview {
            closePreview()
            return
        }

        guard screen == .browser, canGoBack else { return }
        if isLoading, pendingPath != nil {
            loadTask?.cancel()
            loadGeneration = UUID()
            loadTask = nil
            pendingPath = nil
            isLoading = false
            errorMessage = nil
            retryLoadRequest = nil
            return
        }
        guard let previousPath = navigationHistory.last, let server = activeServer else {
            if
                showsDirectFile,
                let server = activeServer,
                !currentPath.isEmpty
            {
                // Consume the direct-file context: if the folder load fails,
                // the error strip owns retry and the next Back leaves for
                // the launcher instead of re-issuing the same failing load.
                showsDirectFile = false
                load(
                    path: currentPath,
                    server: server,
                    previousPath: nil,
                    selectionAfterLoad: remotePath
                )
                return
            }
            loadTask?.cancel()
            loadGeneration = UUID()
            loadTask = nil
            service.shutdown()
            directoryCache.removeAll()
            entries = []
            selectedEntryID = nil
            pendingPath = nil
            isLoading = false
            isRefreshing = false
            errorMessage = nil
            retryLoadRequest = nil
            activeServer = nil
            transfer = nil
            showsDirectFile = false
            selectedServerID = servers.contains(where: { $0.id == selectedServerID })
                ? selectedServerID
                : servers.first?.id
            screen = .launcher
            return
        }
        load(
            path: previousPath,
            server: server,
            previousPath: nil,
            popsHistory: true,
            selectionAfterLoad: currentPath
        )
    }

    func dismissLoadError() {
        errorMessage = nil
        retryLoadRequest = nil
    }

    func select(_ entry: RemoteFileEntry) {
        selectedEntryID = entry.id
    }

    func activate(_ entry: RemoteFileEntry) {
        guard !isLoading else { return }
        select(entry)
        if entry.isDirectory {
            guard let server = activeServer else { return }
            load(path: entry.path, server: server, previousPath: currentPath)
        } else if entry.kind == .symbolicLink {
            openSymbolicLink(entry)
        } else if entry.isPreviewable {
            preview(entry)
        } else {
            download(entry)
        }
    }

    /// A symbolic link may point at a directory or a file; only the remote
    /// side knows. Ask for a directory listing of `link/` — which resolves
    /// the link — and fall back to file treatment (preview by extension,
    /// otherwise download, both following the link server-side) when the
    /// link turns out not to be a directory.
    private func openSymbolicLink(_ entry: RemoteFileEntry) {
        guard let server = activeServer, !isLoading else { return }
        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        errorMessage = nil
        isLoading = true
        pendingPath = screen == .browser ? entry.path : nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedEntries = try await service.listSymlinkTarget(
                    server: server,
                    path: entry.path
                )
                try Task.checkCancellation()
                guard loadGeneration == generation else { return }
                commitLoadedFolder(
                    path: entry.path,
                    entries: loadedEntries,
                    previousPath: currentPath,
                    isRefresh: false,
                    popsHistory: false,
                    selectionAfterLoad: nil
                )
                pendingPath = nil
                isLoading = false
                screen = .browser
            } catch is CancellationError {
                if loadGeneration == generation {
                    pendingPath = nil
                    isLoading = false
                }
            } catch {
                guard loadGeneration == generation else { return }
                pendingPath = nil
                isLoading = false
                errorMessage = nil
                // A killed probe often surfaces as a command failure rather
                // than CancellationError; never start file work for a probe
                // the user already cancelled.
                if Task.isCancelled { return }
                treatSymlinkAsFile(entry)
            }
        }
    }

    private func treatSymlinkAsFile(_ entry: RemoteFileEntry) {
        // Preview and download follow the link server-side, so the entry is
        // reclassified as a regular file; the size on the link line is the
        // link itself, so it is dropped and progress is indeterminate.
        let resolved = RemoteFileEntry(
            name: entry.name,
            path: entry.path,
            kind: .file,
            size: nil,
            modificationText: entry.modificationText
        )
        if resolved.isPreviewable {
            preview(resolved)
        } else {
            download(resolved)
        }
    }

    func preview(_ entry: RemoteFileEntry) {
        guard entry.isPreviewable, let server = activeServer else { return }
        select(entry)
        cleanupPreview()
        previewTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        previewEntry = entry
        previewImage = nil
        previewMarkdown = nil
        isLoadingPreview = true
        errorMessage = nil
        screen = .preview

        previewTask = Task { [weak self] in
            guard let self else { return }
            var pendingPreviewURL: URL?
            defer {
                if let pendingPreviewURL {
                    try? FileManager.default.removeItem(
                        at: pendingPreviewURL.deletingLastPathComponent()
                    )
                }
            }
            do {
                let url = try await service.preparePreview(server: server, entry: entry)
                pendingPreviewURL = url
                try Task.checkCancellation()
                guard previewGeneration == generation else { return }
                let image: NSImage?
                let markdown: RemoteMarkdownDocument?
                if entry.isPreviewableImage {
                    image = try await decodeImage(at: url)
                    markdown = nil
                } else {
                    image = nil
                    markdown = try await markdownDecoder(url)
                }
                try Task.checkCancellation()
                guard previewGeneration == generation else { return }
                previewURL = url
                pendingPreviewURL = nil
                previewImage = image
                previewMarkdown = markdown
                isLoadingPreview = false
            } catch is CancellationError {
                if previewGeneration == generation {
                    isLoadingPreview = false
                }
            } catch {
                if previewGeneration == generation {
                    isLoadingPreview = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func selectPreviewEntry(id: String?) {
        guard
            let id,
            id != previewEntry?.id,
            let entry = previewableEntries.first(where: { $0.id == id })
        else {
            return
        }
        preview(entry)
    }

    @discardableResult
    func movePreviewSelection(by offset: Int) -> Bool {
        let previewableEntries = previewableEntries
        guard
            !previewableEntries.isEmpty,
            let currentID = previewEntry?.id,
            let currentIndex = previewableEntries.firstIndex(where: {
                $0.id == currentID
            })
        else {
            return false
        }
        let targetIndex = min(
            max(currentIndex + offset, previewableEntries.startIndex),
            previewableEntries.index(before: previewableEntries.endIndex)
        )
        guard targetIndex != currentIndex else { return false }
        preview(previewableEntries[targetIndex])
        return true
    }

    func retryPreview() {
        guard let previewEntry else { return }
        preview(previewEntry)
    }

    func closePreview() {
        previewTask?.cancel()
        previewGeneration = UUID()
        previewTask = nil
        cleanupPreview()
        previewEntry = nil
        previewImage = nil
        previewMarkdown = nil
        isLoadingPreview = false
        errorMessage = nil
        screen = .browser
    }

    func download(_ entry: RemoteFileEntry) {
        guard !isTransferRunning else { return }
        guard let destination = presenter.chooseDestination(for: entry) else { return }
        startTransfer(entry: entry, destination: destination)
    }

    func cancelTransfer() {
        guard transfer?.phase == .active else { return }
        transfer?.phase = .cancelling
        transfer?.message = "Stopping transfer…"
        transferTask?.cancel()
    }

    func retryTransfer() {
        guard
            let transfer,
            transfer.phase == .failed || transfer.phase == .cancelled
        else { return }
        self.transfer = nil
        startTransfer(entry: transfer.entry, destination: transfer.destination)
    }

    func dismissTransfer() {
        guard !isTransferRunning else { return }
        transfer = nil
    }

    func revealTransfer() {
        guard let destination = transfer?.destination else { return }
        presenter.revealInFinder(destination)
    }

    func cancelAll() {
        loadTask?.cancel()
        previewTask?.cancel()
        transferTask?.cancel()
        loadGeneration = UUID()
        previewGeneration = UUID()
        transferGeneration = UUID()
        loadTask = nil
        previewTask = nil
        transferTask = nil
        pendingPath = nil
        isLoading = false
        isRefreshing = false
        directoryCache.removeAll()
        service.shutdown()
        cleanupPreview()
    }

    private func load(
        path: String,
        server: RemoteServer,
        previousPath: String?,
        isRefresh: Bool = false,
        popsHistory: Bool = false,
        selectionAfterLoad: String? = nil,
        resolvesFile: Bool = false
    ) {
        let path = RemotePath.normalized(path)
        if isLoading, pendingPath == path {
            return
        }
        if isRefreshing, currentPath == path {
            return
        }

        loadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        errorMessage = nil
        let cachedEntries = isRefresh || resolvesFile
            ? nil
            : directoryCache.entries(
                for: server.connectionIdentity,
                path: path
            )
        let committedFromCache = cachedEntries != nil

        if let cachedEntries {
            commitLoadedFolder(
                path: path,
                entries: cachedEntries,
                previousPath: previousPath,
                isRefresh: false,
                popsHistory: popsHistory,
                selectionAfterLoad: selectionAfterLoad
            )
            pendingPath = nil
            isLoading = false
            isRefreshing = true
            retryLoadRequest = (
                path,
                server,
                nil,
                true,
                false,
                nil,
                false
            )
            screen = .browser
        } else {
            retryLoadRequest = (
                path,
                server,
                previousPath,
                isRefresh,
                popsHistory,
                selectionAfterLoad,
                resolvesFile
            )
            isLoading = !isRefresh
            isRefreshing = isRefresh
            pendingPath = !isRefresh && screen == .browser ? path : nil
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result: RemotePathLoadResult
                if resolvesFile {
                    result = try await service.loadPath(server: server, path: path)
                } else {
                    result = .directory(try await service.list(server: server, path: path))
                }
                try Task.checkCancellation()
                guard loadGeneration == generation else { return }
                switch result {
                case .directory(let loadedEntries):
                    directoryCache.insert(
                        loadedEntries,
                        for: server.connectionIdentity,
                        path: path
                    )
                    commitLoadedFolder(
                        path: path,
                        entries: loadedEntries,
                        previousPath: committedFromCache ? nil : previousPath,
                        isRefresh: committedFromCache || isRefresh,
                        popsHistory: committedFromCache ? false : popsHistory,
                        selectionAfterLoad: committedFromCache ? nil : selectionAfterLoad
                    )
                    screen = .browser
                case .file(let entry):
                    commitLoadedFile(entry)
                    screen = .browser
                }
                pendingPath = nil
                isLoading = false
                isRefreshing = false
                retryLoadRequest = nil
                serverCatalog.recordSuccessfulOpen(server)
                serverCatalog.recordLastOpenedPath(remotePath, for: server)
                refreshServers(preferredConnection: server.connectionIdentity)
                if case .file(let entry) = result, entry.isPreviewable {
                    preview(entry)
                }
            } catch is CancellationError {
                if loadGeneration == generation {
                    pendingPath = nil
                    isLoading = false
                    isRefreshing = false
                }
            } catch {
                if loadGeneration == generation {
                    pendingPath = nil
                    isLoading = false
                    isRefreshing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func commitLoadedFolder(
        path: String,
        entries loadedEntries: [RemoteFileEntry],
        previousPath: String?,
        isRefresh: Bool,
        popsHistory: Bool,
        selectionAfterLoad: String?
    ) {
        if let previousPath {
            navigationHistory.append(previousPath)
        } else if popsHistory, !navigationHistory.isEmpty {
            navigationHistory.removeLast()
        }
        currentPath = path
        remotePath = path
        showsDirectFile = false
        entries = loadedEntries
        if
            let selectionAfterLoad,
            loadedEntries.contains(where: { $0.id == selectionAfterLoad })
        {
            selectedEntryID = selectionAfterLoad
        } else if
            !isRefresh
                || !loadedEntries.contains(where: { $0.id == selectedEntryID })
        {
            selectedEntryID = nil
        }
    }

    private func commitLoadedFile(_ entry: RemoteFileEntry) {
        currentPath = RemotePath.parent(of: entry.path)
        remotePath = entry.path
        showsDirectFile = true
        entries = [entry]
        selectedEntryID = entry.id
    }

    private func decodeImage(at url: URL) async throws -> NSImage {
        let decoder = imageDecoder
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let image = try decoder(url)
            try Task.checkCancellation()
            return DecodedRemoteImage(value: image)
        }
        return try await withTaskCancellationHandler {
            let decoded = try await worker.value.value
            return NSImage(
                cgImage: decoded,
                size: NSSize(width: decoded.width, height: decoded.height)
            )
        } onCancel: {
            worker.cancel()
        }
    }

    private func startTransfer(entry: RemoteFileEntry, destination: URL) {
        guard let server = activeServer else {
            errorMessage = "Reopen the remote folder before downloading."
            return
        }
        let generation = UUID()
        transferGeneration = generation
        transfer = TransferPresentation(
            entry: entry,
            destination: destination,
            completedBytes: 0,
            totalBytes: entry.isDirectory ? nil : entry.size,
            phase: .active
        )

        transferTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.download(
                    server: server,
                    entry: entry,
                    to: destination
                ) { [weak self] completedBytes in
                    Task { @MainActor in
                        guard
                            let self,
                            self.transferGeneration == generation,
                            self.transfer?.phase == .active
                        else { return }
                        self.transfer?.completedBytes = completedBytes
                    }
                }
                try Task.checkCancellation()
                guard transferGeneration == generation else { return }
                transfer?.completedBytes = transfer?.totalBytes ?? transfer?.completedBytes ?? 0
                transfer?.phase = .completed
                transfer?.message = nil
                transferTask = nil
            } catch is CancellationError {
                guard transferGeneration == generation else { return }
                transfer?.phase = .cancelled
                transfer?.message =
                    "Canceled. Temporary data was removed; existing files were unchanged."
                transferTask = nil
            } catch {
                guard transferGeneration == generation else { return }
                transfer?.phase = .failed
                transfer?.message =
                    "\(error.localizedDescription) Temporary data was removed; "
                    + "existing files were unchanged."
                transferTask = nil
            }
        }
    }

    private func cleanupPreview() {
        if let previewURL {
            try? FileManager.default.removeItem(at: previewURL.deletingLastPathComponent())
        }
        previewURL = nil
    }

    private func prefillLastPathForSelectedServer() {
        guard let server = selectedServer else { return }
        remotePath = serverCatalog.lastOpenedPath(for: server) ?? ""
    }

    private func refreshServers(
        preferredConnection: RemoteServer.ConnectionIdentity?
    ) {
        let updatedServers = serverCatalog.servers(from: tunnels)
        servers = updatedServers
        if
            let preferredConnection,
            let preferred = updatedServers.first(where: {
                $0.connectionIdentity == preferredConnection
            })
        {
            selectedServerID = preferred.id
        } else {
            selectedServerID = updatedServers.first?.id
        }
    }

    private var isTransferRunning: Bool {
        transfer?.phase == .active || transfer?.phase == .cancelling
    }
}
