import Darwin
import Foundation

protocol RemoteFileServing: AnyObject, Sendable {
    func loadPath(server: RemoteServer, path: String) async throws -> RemotePathLoadResult
    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry]
    /// Lists the target of a symbolic link as a directory. The trailing
    /// slash makes the remote stat resolve the link, so this succeeds for a
    /// symlink to a directory and fails for a link to a file or a dangling
    /// link. A protocol requirement (not just an extension default) so
    /// existential callers dispatch to the concrete implementation.
    func listSymlinkTarget(
        server: RemoteServer,
        path: String
    ) async throws -> [RemoteFileEntry]
    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws
    func preparePreview(server: RemoteServer, entry: RemoteFileEntry) async throws -> URL
    func upload(
        server: RemoteServer,
        localFile: URL,
        remoteDirectory: String,
        replaceExisting: Bool,
        phase: @escaping @Sendable (RemoteUploadPhase) -> Void
    ) async throws
    func shutdown()
}

extension RemoteFileServing {
    /// Lists the target of a symbolic link. The trailing slash makes the
    /// remote stat resolve the link, so this succeeds for a symlink to a
    /// directory and fails for a link to a file or a dangling link.
    func listSymlinkTarget(
        server: RemoteServer,
        path: String
    ) async throws -> [RemoteFileEntry] {
        throw RemoteFileError.commandFailed("Symbolic links are not supported.")
    }
}

extension RemoteFileServing {
    func loadPath(server: RemoteServer, path: String) async throws -> RemotePathLoadResult {
        .directory(try await list(server: server, path: path))
    }

    func shutdown() {}

    func upload(
        server: RemoteServer,
        localFile: URL,
        remoteDirectory: String,
        replaceExisting: Bool,
        phase: @escaping @Sendable (RemoteUploadPhase) -> Void
    ) async throws {
        throw RemoteFileError.uploadCapabilityUnavailable("remote publication")
    }

    func upload(
        server: RemoteServer,
        localFile: URL,
        remoteDirectory: String,
        replaceExisting: Bool
    ) async throws {
        try await upload(
            server: server,
            localFile: localFile,
            remoteDirectory: remoteDirectory,
            replaceExisting: replaceExisting
        ) { _ in }
    }
}

/// Pin the chosen inode before SSH work; sftp must never reopen a mutable path.
private struct LocalUploadSnapshot {
    private static let copyBufferSize = 64 * 1_024
    private static let permissionMask = mode_t(S_IRWXU | S_IRWXG | S_IRWXO)
    private static let privateFileMode = mode_t(S_IRUSR | S_IWUSR)

    let url: URL
    private let directory: URL
    private let fileManager: FileManager

    init(source: URL, fileManager: FileManager) throws {
        let descriptor = Darwin.open(
            source.path,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw RemoteFileError.invalidUploadSource }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }

        var attributes = stat()
        guard
            fstat(descriptor, &attributes) == 0,
            attributes.st_mode & S_IFMT == S_IFREG,
            attributes.st_size >= 0
        else {
            throw RemoteFileError.invalidUploadSource
        }
        try Task.checkCancellation()

        var template = Array(fileManager.temporaryDirectory
            .appendingPathComponent("RelayBarUpload-XXXXXX").path.utf8CString)
        let directory = try template.withUnsafeMutableBufferPointer { buffer -> URL in
            guard let base = buffer.baseAddress, let path = mkdtemp(base) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        let payload = directory.appendingPathComponent("payload")

        do {
            let outputDescriptor = Darwin.open(
                payload.path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                Self.privateFileMode
            )
            guard outputDescriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
            defer { try? output.close() }

            // Bound memory and stop at the opened file's size, even if it grows.
            var remaining = attributes.st_size
            while remaining > 0 {
                try Task.checkCancellation()
                let count = Int(min(Int64(Self.copyBufferSize), remaining))
                guard let data = try input.read(upToCount: count), !data.isEmpty else {
                    throw RemoteFileError.invalidUploadSource
                }
                try output.write(contentsOf: data)
                remaining -= Int64(data.count)
            }
            try Task.checkCancellation()

            // Preserve upload modes; the enclosing 0700 directory keeps bytes private.
            guard fchmod(outputDescriptor, attributes.st_mode & Self.permissionMask) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        self.url = payload
        self.directory = directory
        self.fileManager = fileManager
    }

    func remove() {
        try? fileManager.removeItem(at: directory)
    }
}

/// Configuration is immutable after initialization. Each command owns separate
/// process state, and the small boxes shared with callbacks synchronize access.
final class SFTPRemoteFileService: RemoteFileServing, @unchecked Sendable {
    private enum UploadPublication: Equatable {
        case notAttempted
        case unconfirmed
        case confirmed
    }

    private enum CapturedStandardOutput {
        case text(String)
        case invalidUTF8
        case unreadable
    }

    private struct CommandResult {
        let status: Int32
        let output: CapturedStandardOutput
        let error: String
        /// True when either the output or diagnostics capture exceeds its byte cap.
        let exceededCaptureLimit: Bool
        let sessionToken: String?
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private let forceStopDelay: TimeInterval
        private let signalProcess: @Sendable (pid_t, Int32) -> Int32
        private var processIdentifier: pid_t?
        private var exitSource: DispatchSourceProcess?
        private var exitHandler: (@Sendable (Int32) -> Void)?
        private var cancellationRequested = false
        private var forceStopScheduled = false
        private var terminationSignalSent = false

        init(
            forceStopDelay: TimeInterval,
            signalProcess: @escaping @Sendable (pid_t, Int32) -> Int32
        ) {
            self.forceStopDelay = forceStopDelay
            self.signalProcess = signalProcess
        }

        var shouldStart: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !cancellationRequested
        }

        func beginWaiting(
            for processIdentifier: pid_t,
            onExit: @escaping @Sendable (Int32) -> Void
        ) {
            lock.lock()
            self.processIdentifier = processIdentifier
            exitHandler = onExit
            let exitSource = DispatchSource.makeProcessSource(
                identifier: processIdentifier,
                eventMask: .exit,
                queue: DispatchQueue.global(qos: .utility)
            )
            self.exitSource = exitSource
            exitSource.setEventHandler { [weak self] in
                self?.processDidExit()
            }
            exitSource.resume()
            lock.unlock()
        }

        func cancel() {
            var shouldScheduleForceStop = false
            lock.lock()
            cancellationRequested = true
            if let processIdentifier {
                if !terminationSignalSent {
                    terminationSignalSent = true
                    _ = signalProcess(processIdentifier, SIGTERM)
                }
                if !forceStopScheduled {
                    forceStopScheduled = true
                    shouldScheduleForceStop = true
                }
            }
            lock.unlock()

            if shouldScheduleForceStop {
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + forceStopDelay
                ) {
                    [weak self] in
                    self?.forceStop()
                }
            }
        }

        @discardableResult
        func stopIfCancellationRequested() -> Bool {
            lock.lock()
            let wasRequested = cancellationRequested
            lock.unlock()
            if wasRequested {
                cancel()
            }
            return wasRequested
        }

        private func processDidExit() {
            lock.lock()
            let completion = reapExitedProcessLocked()
            let shouldRetry = processIdentifier != nil
            lock.unlock()
            complete(completion)
            if shouldRetry {
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .milliseconds(10)
                ) { [weak self] in
                    self?.processDidExit()
                }
            }
        }

        private func forceStop() {
            lock.lock()
            let completion = reapExitedProcessLocked()
            if completion == nil, let processIdentifier {
                // Reaping and signalling share this lock. If the child exits
                // after the nonblocking wait, it remains an unreaped zombie
                // until this signal attempt finishes, so its PID cannot be
                // recycled and the signal cannot reach an unrelated process.
                _ = signalProcess(processIdentifier, SIGKILL)
            }
            lock.unlock()
            complete(completion)
        }

        private func reapExitedProcessLocked() -> (
            handler: @Sendable (Int32) -> Void,
            status: Int32
        )? {
            guard let processIdentifier else { return nil }
            var waitStatus: Int32 = 0
            let result = waitpid(processIdentifier, &waitStatus, WNOHANG)
            if result == processIdentifier {
                return finishLocked(status: Self.terminationStatus(from: waitStatus))
            }
            if result == -1, errno != EINTR {
                return finishLocked(status: -1)
            }
            return nil
        }

        private func finishLocked(status: Int32) -> (
            handler: @Sendable (Int32) -> Void,
            status: Int32
        )? {
            processIdentifier = nil
            exitSource?.cancel()
            exitSource = nil
            guard let exitHandler else { return nil }
            self.exitHandler = nil
            return (exitHandler, status)
        }

        private func complete(
            _ completion: (
                handler: @Sendable (Int32) -> Void,
                status: Int32
            )?
        ) {
            if let completion {
                completion.handler(completion.status)
            }
        }

        private static func terminationStatus(from waitStatus: Int32) -> Int32 {
            let signal = waitStatus & 0x7F
            if signal == 0 {
                return (waitStatus >> 8) & 0xFF
            }
            return signal
        }
    }

    private final class OutputLimitBox: @unchecked Sendable {
        private let lock = NSLock()
        private var exceeded = false

        func markExceeded() {
            lock.lock()
            exceeded = true
            lock.unlock()
        }

        var hasExceeded: Bool {
            lock.lock()
            defer { lock.unlock() }
            return exceeded
        }
    }

    private final class CapabilityBox: @unchecked Sendable {
        private struct Entry {
            let capabilities: RemoteUploadCapabilities
            let sessionToken: String?
        }

        private let lock = NSLock()
        private var values: [RemoteServer.ConnectionIdentity: Entry] = [:]

        func value(
            for identity: RemoteServer.ConnectionIdentity,
            sessionToken: String?
        ) -> RemoteUploadCapabilities? {
            lock.lock()
            defer { lock.unlock() }
            guard values[identity]?.sessionToken == sessionToken else { return nil }
            return values[identity]?.capabilities
        }

        func store(
            _ value: RemoteUploadCapabilities,
            for identity: RemoteServer.ConnectionIdentity,
            sessionToken: String?
        ) {
            lock.lock()
            values[identity] = Entry(
                capabilities: value,
                sessionToken: sessionToken
            )
            lock.unlock()
        }

        func removeAll() {
            lock.lock()
            values.removeAll()
            lock.unlock()
        }
    }

    private let executableURL: URL
    private let fileManager: FileManager
    private let previewSizeLimit: Int64
    private let markdownPreviewSizeLimit: Int64
    private let standardOutputLimit: Int64
    private let standardErrorLimit: Int64
    private let forceStopDelay: TimeInterval
    private let signalProcess: @Sendable (pid_t, Int32) -> Int32
    private let connectionSession: RemoteFileSSHSession?
    private let uploadCleanupTimeout: Duration
    private let capabilityBox = CapabilityBox()

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/sftp"),
        fileManager: FileManager = .default,
        previewSizeLimit: Int64 = 100 * 1_024 * 1_024,
        markdownPreviewSizeLimit: Int64 = Int64(RemoteMarkdownDecoder.maximumByteCount),
        standardOutputLimit: Int64 = 32 * 1_024 * 1_024,
        standardErrorLimit: Int64 = 1 * 1_024 * 1_024,
        forceStopDelay: TimeInterval = 2,
        uploadCleanupTimeout: Duration = .seconds(10),
        connectionSharing: Bool = true,
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        sessionTemporaryDirectory: URL? = nil,
        processEnvironment: [String: String]? = nil,
        signalProcess: @escaping @Sendable (pid_t, Int32) -> Int32 = {
            Darwin.kill($0, $1)
        }
    ) {
        self.executableURL = executableURL
        self.fileManager = fileManager
        self.previewSizeLimit = previewSizeLimit
        self.markdownPreviewSizeLimit = markdownPreviewSizeLimit
        self.standardOutputLimit = standardOutputLimit
        self.standardErrorLimit = standardErrorLimit
        self.forceStopDelay = forceStopDelay
        self.uploadCleanupTimeout = uploadCleanupTimeout
        self.signalProcess = signalProcess
        connectionSession = connectionSharing
            ? RemoteFileSSHSession(
                executableURL: sshExecutableURL,
                fileManager: fileManager,
                temporaryDirectory: sessionTemporaryDirectory,
                processEnvironment: processEnvironment,
                forceStopDelay: forceStopDelay,
                signalProcess: signalProcess
            )
            : nil
    }

    func shutdown() {
        capabilityBox.removeAll()
        connectionSession?.shutdown()
    }

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        let (output, normalizedPath) = try await listingOutput(server: server, path: path)
        return try SFTPListingParser.parse(output, parentPath: normalizedPath)
    }

    func loadPath(server: RemoteServer, path: String) async throws -> RemotePathLoadResult {
        let (output, normalizedPath) = try await listingOutput(server: server, path: path)
        return try SFTPListingParser.parsePath(output, path: normalizedPath)
    }

    /// Lists the target of a symbolic link as a directory. The trailing
    /// slash is significant: the remote side resolves `link/` through the
    /// link to the directory it points at, while `link` alone would list the
    /// link itself. A link to a file (or a dangling link) fails here, which
    /// the model treats as "the link is a file".
    func listSymlinkTarget(
        server: RemoteServer,
        path: String
    ) async throws -> [RemoteFileEntry] {
        guard RemotePath.validationMessage(for: path) == nil else {
            throw RemoteFileError.invalidPath
        }
        let normalizedPath = RemotePath.normalized(path)
        let listingPath = normalizedPath == "/"
            ? "/"
            : normalizedPath + "/"
        let result = try await run(
            server: server,
            batchInput: SFTPCommandBuilder.listCommand(path: listingPath)
        )
        try validate(result)
        return try SFTPListingParser.parse(
            Self.decodedListing(result),
            parentPath: normalizedPath
        )
    }

    private func listingOutput(
        server: RemoteServer,
        path: String,
        requiredSessionToken: String? = nil
    ) async throws -> (output: String, normalizedPath: String) {
        guard RemotePath.validationMessage(for: path) == nil else {
            throw RemoteFileError.invalidPath
        }
        let normalizedPath = RemotePath.normalized(path)
        let result = try await run(
            server: server,
            batchInput: SFTPCommandBuilder.listCommand(path: normalizedPath),
            requiredSessionToken: requiredSessionToken
        )
        try validate(result)
        return (try Self.decodedListing(result), normalizedPath)
    }

    private func decodedListingOutput(
        server: RemoteServer,
        path: String,
        requiredSessionToken: String?
    ) async throws -> String {
        try await listingOutput(
            server: server,
            path: path,
            requiredSessionToken: requiredSessionToken
        ).output
    }

    /// One decoding path for every listing, so a caller cannot bypass the
    /// invalid-UTF-8 and unreadable rejections by reading `result.output`
    /// directly — which is exactly how the symbolic-link listing came to
    /// hand a raw captured value to a parser expecting text.
    private static func decodedListing(_ result: CommandResult) throws -> String {
        switch result.output {
        case .text(let text):
            return text
        case .invalidUTF8:
            throw RemoteFileError.invalidListingEncoding
        case .unreadable:
            throw RemoteFileError.unreadableListing
        }
    }

    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await download(
            server: server,
            entry: entry,
            to: destination,
            maximumBytes: nil,
            progress: progress
        )
    }

    private func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        maximumBytes: Int64?,
        limitError: RemoteFileError = .previewTooLarge,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingDirectory = parent.appendingPathComponent(
            ".relaybar-\(UUID().uuidString).partial",
            isDirectory: true
        )
        let partial = stagingDirectory.appendingPathComponent(
            "payload",
            isDirectory: entry.isDirectory
        )
        var ownsStagingDirectory = false

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            ownsStagingDirectory = true
            let command = try SFTPCommandBuilder.downloadCommand(
                remotePath: entry.path,
                localPath: partial.path,
                recursively: entry.isDirectory
            )
            try await runTransfer(
                server: server,
                batchInput: command,
                partialURL: partial,
                maximumBytes: maximumBytes,
                limitError: limitError,
                progress: progress
            )
            try Task.checkCancellation()
            if let maximumBytes, localSize(of: partial) > maximumBytes {
                throw limitError
            }
            guard fileManager.fileExists(atPath: partial.path) else {
                throw RemoteFileError.missingDownload
            }
            // Lock the payload down while it is still staged: moveItem
            // preserves permissions, so without this a first-time download
            // would sit at its final path with loose modes until the chmod
            // below ran.
            securePartialPermissions(at: partial)

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: partial,
                    backupItemName: nil
                )
            } else {
                try fileManager.moveItem(at: partial, to: destination)
            }
            // replaceItemAt keeps the *replaced* item's attributes, so the
            // payload must be locked down here, not at the staging path:
            // owner-only, as the staging directory's 0700 already promised.
            securePartialPermissions(at: destination)
            try? fileManager.removeItem(at: stagingDirectory)
        } catch {
            if ownsStagingDirectory {
                try? fileManager.removeItem(at: stagingDirectory)
            }
            throw error
        }
    }

    func preparePreview(server: RemoteServer, entry: RemoteFileEntry) async throws -> URL {
        let maximumBytes = entry.isPreviewableMarkdown
            ? markdownPreviewSizeLimit
            : previewSizeLimit
        let limitError: RemoteFileError = entry.isPreviewableMarkdown
            ? .markdownTooLarge
            : .previewTooLarge
        if let size = entry.size, size > maximumBytes {
            throw limitError
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("RelayBarPreview-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = directory.appendingPathComponent(entry.name)

        do {
            try await download(
                server: server,
                entry: entry,
                to: destination,
                maximumBytes: maximumBytes,
                limitError: limitError
            ) { _ in }
            return destination
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func upload(
        server: RemoteServer,
        localFile: URL,
        remoteDirectory: String,
        replaceExisting: Bool,
        phase: @escaping @Sendable (RemoteUploadPhase) -> Void
    ) async throws {
        let values = try localFile.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true,
            let fileSize = values.fileSize,
            fileSize >= 0
        else {
            throw RemoteFileError.invalidUploadSource
        }
        guard RemotePath.validationMessage(for: remoteDirectory) == nil else {
            throw RemoteFileError.invalidPath
        }

        let directory = RemotePath.normalized(remoteDirectory)
        let name = localFile.lastPathComponent
        guard !name.isEmpty else { throw RemoteFileError.invalidUploadSource }
        let target = RemotePath.joining(directory, name)
        guard RemotePath.validationMessage(for: target) == nil else {
            throw RemoteFileError.invalidPath
        }

        let snapshot = try LocalUploadSnapshot(source: localFile, fileManager: fileManager)
        defer { snapshot.remove() }

        let initialEntries = try await list(server: server, path: directory)
        if let existing = initialEntries.first(where: { $0.name == name }) {
            guard existing.kind == .file else {
                throw RemoteFileError.unsupportedUploadTarget
            }
            guard replaceExisting else {
                throw RemoteFileError.uploadConflict
            }
        }

        let capabilityContext = try await uploadCapabilities(for: server)
        let capabilities = capabilityContext.capabilities
        if replaceExisting {
            guard capabilities.supportsPOSIXRename else {
                throw RemoteFileError.uploadCapabilityUnavailable("atomic replace")
            }
        } else {
            guard capabilities.supportsHardLink else {
                throw RemoteFileError.uploadCapabilityUnavailable("no-overwrite publish")
            }
        }

        let stagingName = ".relaybar-upload-\(UUID().uuidString).partial"
        let staging = RemotePath.joining(directory, stagingName)
        guard RemotePath.validationMessage(for: staging) == nil else {
            throw RemoteFileError.invalidPath
        }

        var ownsStaging = false
        var publication = UploadPublication.notAttempted
        do {
            // `put` may create the staging entry before its child is cancelled
            // or reports failure. Claim the exact name before launching it so
            // every post-launch exit attempts bounded cleanup.
            ownsStaging = true
            phase(.staging)
            let uploadResult = try await run(
                server: server,
                batchInput: SFTPCommandBuilder.uploadCommand(
                    localPath: snapshot.url.path,
                    remotePath: staging
                ),
                requiredSessionToken: capabilityContext.sessionToken
            )
            try validate(uploadResult)
            try Task.checkCancellation()

            phase(.publishing)
            let finalEntries = try SFTPListingParser.parse(
                try await decodedListingOutput(
                    server: server,
                    path: directory,
                    requiredSessionToken: capabilityContext.sessionToken
                ),
                parentPath: directory
            )
            if let existing = finalEntries.first(where: { $0.name == name }) {
                guard existing.kind == .file else {
                    throw RemoteFileError.unsupportedUploadTarget
                }
                guard replaceExisting else {
                    throw RemoteFileError.uploadConflict
                }
            }

            let publishCommand = replaceExisting
                ? try SFTPCommandBuilder.renameCommand(
                    existingPath: staging,
                    newPath: target
                )
                : try SFTPCommandBuilder.hardLinkCommand(
                    existingPath: staging,
                    newPath: target
                )
            try Task.checkCancellation()
            // Once sent, cancellation cannot prove whether the server committed it.
            publication = .unconfirmed
            let publishResult = try await run(
                server: server,
                batchInput: publishCommand,
                requiredSessionToken: capabilityContext.sessionToken
            )
            do {
                try validate(publishResult)
                publication = .confirmed
            } catch {
                let diagnosticEntries = try? SFTPListingParser.parse(
                    try await decodedListingOutput(
                        server: server,
                        path: directory,
                        requiredSessionToken: capabilityContext.sessionToken
                    ),
                    parentPath: directory
                )
                if !replaceExisting,
                   diagnosticEntries?.contains(where: { $0.name == name }) == true
                {
                    throw RemoteFileError.uploadConflict
                }
                throw error
            }

            if replaceExisting {
                ownsStaging = false
            } else {
                phase(.cleaningUp)
                try await removeUploadStaging(server: server, path: staging)
                ownsStaging = false
            }
        } catch {
            let uploadError: Error = publication == .unconfirmed && error is CancellationError
                ? RemoteFileError.uploadPublicationUnconfirmed
                : error
            if ownsStaging {
                phase(.cleaningUp)
                let cleaned = await cleanupUploadStaging(server: server, path: staging)
                if !cleaned {
                    let context = publication == .confirmed
                        ? "The upload was published."
                        : uploadError.localizedDescription
                    throw RemoteFileError.uploadCleanupUnconfirmed(context)
                }
                if publication == .confirmed { return }
            }
            throw uploadError
        }
    }

    private func uploadCapabilities(
        for server: RemoteServer
    ) async throws -> (
        capabilities: RemoteUploadCapabilities,
        sessionToken: String?
    ) {
        let sessionToken: String?
        if let connectionSession {
            sessionToken = try await connectionSession.controlSocket(for: server).path
        } else {
            sessionToken = nil
        }
        if let cached = capabilityBox.value(
            for: server.connectionIdentity,
            sessionToken: sessionToken
        ) {
            return (cached, sessionToken)
        }
        let result = try await run(
            server: server,
            batchInput: SFTPCommandBuilder.quitCommand,
            diagnosticLevel: 2,
            requiredSessionToken: sessionToken
        )
        try validate(result)
        let capabilities = RemoteUploadCapabilities.parse(result.error)
        capabilityBox.store(
            capabilities,
            for: server.connectionIdentity,
            sessionToken: result.sessionToken
        )
        return (capabilities, result.sessionToken)
    }

    private func removeUploadStaging(server: RemoteServer, path: String) async throws {
        // Deadline cancellation reaches the child; the group waits for its reaping.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                let result = try await run(
                    server: server,
                    batchInput: SFTPCommandBuilder.removeCommand(path: path)
                )
                try validate(result)
            }
            group.addTask { [uploadCleanupTimeout] in
                try await Task.sleep(for: uploadCleanupTimeout)
                throw RemoteFileError.commandFailed("Remote staging cleanup timed out.")
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private func cleanupUploadStaging(server: RemoteServer, path: String) async -> Bool {
        // Recovery survives user cancellation, but retains its own cleanup deadline.
        let task = Task.detached { [self] in
            do {
                try await removeUploadStaging(server: server, path: path)
                return true
            } catch {
                return false
            }
        }
        return await task.value
    }

    private func runTransfer(
        server: RemoteServer,
        batchInput: String,
        partialURL: URL,
        maximumBytes: Int64?,
        limitError: RemoteFileError,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            let isDirectory = partialURL.hasDirectoryPath
            group.addTask { [self] in
                let result = try await run(server: server, batchInput: batchInput)
                try validate(result)
                return true
            }
            group.addTask { [self] in
                var pollingInterval = Self.progressPollingInterval(
                    forEntryCount: 0,
                    isDirectory: isDirectory
                )
                while !Task.isCancelled {
                    securePartialPermissions(at: partialURL)
                    let measurement = measureLocal(partialURL)
                    progress(measurement.bytes)
                    if let maximumBytes, measurement.bytes > maximumBytes {
                        throw limitError
                    }
                    // Each poll re-walks the tree, so widen the gap as the tree
                    // grows instead of paying an O(entries) walk every second.
                    pollingInterval = Self.progressPollingInterval(
                        forEntryCount: measurement.entries,
                        isDirectory: isDirectory
                    )
                    try await Task.sleep(for: pollingInterval)
                }
                return false
            }

            while let commandFinished = try await group.next() {
                if commandFinished {
                    progress(localSize(of: partialURL))
                    group.cancelAll()
                    return
                }
            }
        }
    }

    private func run(
        server: RemoteServer,
        batchInput: String,
        diagnosticLevel: Int = 0,
        requiredSessionToken: String? = nil
    ) async throws -> CommandResult {
        let controlSocket: URL?
        if let connectionSession {
            controlSocket = try await connectionSession.controlSocket(for: server)
        } else {
            controlSocket = nil
        }
        try Task.checkCancellation()
        if let requiredSessionToken, controlSocket?.path != requiredSessionToken {
            throw RemoteFileError.connectionSessionUnavailable
        }
        if
            let controlSocket,
            !fileManager.fileExists(atPath: controlSocket.path)
        {
            throw RemoteFileError.connectionSessionUnavailable
        }
        let arguments = try SFTPCommandBuilder.processArguments(
            for: server,
            controlSocket: controlSocket,
            diagnosticLevel: diagnosticLevel
        )
        let processBox = ProcessBox(
            forceStopDelay: forceStopDelay,
            signalProcess: signalProcess
        )
        let outputLimitBox = OutputLimitBox()
        let outputLimit = standardOutputLimit
        let errorLimit = standardErrorLimit

        return try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<CommandResult, Error>) in
                let temporaryDirectory = fileManager.temporaryDirectory
                    .appendingPathComponent("RelayBarSFTP-\(UUID().uuidString)", isDirectory: true)

                do {
                    try fileManager.createDirectory(
                        at: temporaryDirectory,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    let outputURL = temporaryDirectory.appendingPathComponent("stdout")
                    let errorURL = temporaryDirectory.appendingPathComponent("stderr")
                    fileManager.createFile(
                        atPath: outputURL.path,
                        contents: nil,
                        attributes: [.posixPermissions: 0o600]
                    )
                    fileManager.createFile(
                        atPath: errorURL.path,
                        contents: nil,
                        attributes: [.posixPermissions: 0o600]
                    )

                    let inputPipe = Pipe()
                    try Self.suppressSIGPIPE(
                        on: inputPipe.fileHandleForWriting.fileDescriptor
                    )
                    let outputMonitor = DispatchSource.makeTimerSource(
                        queue: DispatchQueue(label: "RelayBar.SFTPOutputLimit")
                    )

                    outputMonitor.schedule(
                        deadline: .now() + .milliseconds(250),
                        repeating: .milliseconds(250)
                    )
                    outputMonitor.setEventHandler {
                        let outputSize = Self.fileSize(at: outputURL)
                        let errorSize = Self.fileSize(at: errorURL)
                        guard
                            outputSize > outputLimit
                                || errorSize > errorLimit
                        else { return }
                        outputLimitBox.markExceeded()
                        processBox.cancel()
                    }

                    let finish: @Sendable (Int32) -> Void = { status in
                        outputMonitor.cancel()
                        if
                            Self.fileSize(at: outputURL) > outputLimit
                                || Self.fileSize(at: errorURL) > errorLimit
                        {
                            outputLimitBox.markExceeded()
                        }
                        let capturedOutput = Self.readUTF8String(
                            at: outputURL,
                            maximumBytes: outputLimit
                        )
                        let capturedError = Self.readDiagnosticString(
                            at: errorURL,
                            maximumBytes: errorLimit
                        )
                        let exceededCaptureLimit = outputLimitBox.hasExceeded
                            || capturedOutput.exceededLimit
                            || capturedError.exceededLimit
                        try? FileManager.default.removeItem(at: temporaryDirectory)
                        continuation.resume(
                            returning: CommandResult(
                                status: status,
                                output: capturedOutput.output,
                                error: capturedError.text,
                                exceededCaptureLimit: exceededCaptureLimit,
                                sessionToken: controlSocket?.path
                            )
                        )
                    }

                    do {
                        outputMonitor.resume()
                        guard processBox.shouldStart else {
                            throw CancellationError()
                        }
                        if
                            let controlSocket,
                            !fileManager.fileExists(atPath: controlSocket.path)
                        {
                            throw RemoteFileError.connectionSessionUnavailable
                        }
                        let processIdentifier = try Self.spawnProcess(
                            executableURL: executableURL,
                            arguments: arguments,
                            inputPipe: inputPipe,
                            outputURL: outputURL,
                            errorURL: errorURL
                        )
                        inputPipe.fileHandleForReading.closeFile()
                        processBox.beginWaiting(
                            for: processIdentifier,
                            onExit: finish
                        )
                    } catch {
                        outputMonitor.cancel()
                        inputPipe.fileHandleForReading.closeFile()
                        inputPipe.fileHandleForWriting.closeFile()
                        try? fileManager.removeItem(at: temporaryDirectory)
                        continuation.resume(throwing: error)
                        return
                    }

                    if processBox.stopIfCancellationRequested() {
                        inputPipe.fileHandleForWriting.closeFile()
                        return
                    }

                    do {
                        try inputPipe.fileHandleForWriting.write(contentsOf: Data(batchInput.utf8))
                    } catch {
                        processBox.cancel()
                    }
                    try? inputPipe.fileHandleForWriting.close()
                } catch {
                    try? fileManager.removeItem(at: temporaryDirectory)
                    continuation.resume(throwing: error)
                }
            }
            if Task.isCancelled, result.status != 0 {
                throw CancellationError()
            }
            return result
        } onCancel: {
            processBox.cancel()
        }
    }

    /// Kept internal so the descriptor-level guarantee has deterministic
    /// coverage without relying on a scheduling race against a short-lived child.
    static func suppressSIGPIPE(on fileDescriptor: Int32) throws {
        guard fcntl(fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw posixError(errno)
        }
    }

    /// Kept internal so descriptor-zero inheritance has deterministic
    /// coverage without changing the test process's standard input asynchronously.
    static func spawnProcess(
        executableURL: URL,
        arguments: [String],
        inputPipe: Pipe,
        outputURL: URL,
        errorURL: URL
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        let actionsResult = posix_spawn_file_actions_init(&actions)
        guard actionsResult == 0 else {
            throw posixError(actionsResult)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        let inputDescriptor = inputPipe.fileHandleForReading.fileDescriptor
        let inputWriteDescriptor = inputPipe.fileHandleForWriting.fileDescriptor

        // Under POSIX_SPAWN_CLOEXEC_DEFAULT, even an existing descriptor zero
        // must be named by a file action to survive into the child.
        let duplicateInput = posix_spawn_file_actions_adddup2(
            &actions,
            inputDescriptor,
            STDIN_FILENO
        )
        guard duplicateInput == 0 else {
            throw posixError(duplicateInput)
        }
        if inputDescriptor != STDIN_FILENO {
            let closeInput = posix_spawn_file_actions_addclose(&actions, inputDescriptor)
            guard closeInput == 0 else {
                throw posixError(closeInput)
            }
        }
        let closeInputWriter = posix_spawn_file_actions_addclose(
            &actions,
            inputWriteDescriptor
        )
        guard closeInputWriter == 0 else {
            throw posixError(closeInputWriter)
        }
        let openOutput = outputURL.path.withCString { outputPath in
            posix_spawn_file_actions_addopen(
                &actions,
                STDOUT_FILENO,
                outputPath,
                O_WRONLY | O_TRUNC,
                mode_t(0o600)
            )
        }
        guard openOutput == 0 else {
            throw posixError(openOutput)
        }
        let openError = errorURL.path.withCString { errorPath in
            posix_spawn_file_actions_addopen(
                &actions,
                STDERR_FILENO,
                errorPath,
                O_WRONLY | O_TRUNC,
                mode_t(0o600)
            )
        }
        guard openError == 0 else {
            throw posixError(openError)
        }

        var attributes: posix_spawnattr_t?
        let attributesResult = posix_spawnattr_init(&attributes)
        guard attributesResult == 0 else {
            throw posixError(attributesResult)
        }
        defer { posix_spawnattr_destroy(&attributes) }

        var defaultSignals = sigset_t()
        guard sigfillset(&defaultSignals) == 0 else {
            throw posixError(errno)
        }
        _ = sigdelset(&defaultSignals, SIGKILL)
        _ = sigdelset(&defaultSignals, SIGSTOP)
        var signalMask = sigset_t()
        guard sigemptyset(&signalMask) == 0 else {
            throw posixError(errno)
        }
        let signalConfiguration = [
            posix_spawnattr_setsigdefault(&attributes, &defaultSignals),
            posix_spawnattr_setsigmask(&attributes, &signalMask)
        ]
        if let error = signalConfiguration.first(where: { $0 != 0 }) {
            throw posixError(error)
        }

        let flagsResult = posix_spawnattr_setflags(
            &attributes,
            Int16(
                POSIX_SPAWN_CLOEXEC_DEFAULT
                    | POSIX_SPAWN_SETSIGDEF
                    | POSIX_SPAWN_SETSIGMASK
            )
        )
        guard flagsResult == 0 else {
            throw posixError(flagsResult)
        }

        var argumentPointers: [UnsafeMutablePointer<CChar>?] = []
        defer {
            for argumentPointer in argumentPointers {
                free(argumentPointer)
            }
        }
        for argument in [executableURL.path] + arguments {
            guard let argumentPointer = strdup(argument) else {
                throw POSIXError(.ENOMEM)
            }
            argumentPointers.append(argumentPointer)
        }
        argumentPointers.append(nil)

        var processIdentifier: pid_t = 0
        let spawnResult = executableURL.path.withCString { executablePath in
            argumentPointers.withUnsafeMutableBufferPointer { buffer in
                posix_spawn(
                    &processIdentifier,
                    executablePath,
                    &actions,
                    &attributes,
                    buffer.baseAddress!,
                    environ
                )
            }
        }
        guard spawnResult == 0 else {
            throw posixError(spawnResult)
        }
        return processIdentifier
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    private func validate(_ result: CommandResult) throws {
        if result.exceededCaptureLimit {
            throw RemoteFileError.responseTooLarge
        }
        guard result.status == 0 else {
            throw RemoteFileError.commandFailed(Self.friendlyMessage(from: result.error))
        }
    }

    /// Ordered: the first entry whose text appears in the detail wins, so
    /// overlapping matches resolve the same way they did as a branch chain.
    private static let messageTable: [(matches: [String], message: String)] = [
        (["permission denied"], "Permission was denied for this server or path."),
        (["host key verification failed"], "SSH could not verify this server’s host key."),
        (["no such file", "not found"], "The remote path wasn’t found."),
        (["could not resolve hostname"], "The saved server could not be found."),
        (["operation timed out", "connection timed out"], "The connection timed out."),
        (["connection refused"], "The server refused the connection."),
        (["connection closed", "connection reset"], "The connection was lost.")
    ]

    static func friendlyMessage(from errorOutput: String) -> String {
        let lines = errorOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter {
                let lowercase = $0.lowercased()
                return !$0.hasPrefix("sftp>")
                    && !lowercase.hasPrefix("debug1:")
                    && !lowercase.hasPrefix("debug2:")
                    && !lowercase.hasPrefix("debug3:")
            }
        let rawDetail = lines.suffix(2).joined(separator: " ")
        let safeScalars = rawDetail.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let detail = String(String.UnicodeScalarView(safeScalars).prefix(512))

        let match = Self.messageTable.first { entry in
            entry.matches.contains { detail.localizedCaseInsensitiveContains($0) }
        }
        if let match { return match.message }
        return detail.isEmpty ? "The remote operation failed." : detail
    }

    /// Progress polling scales with how much of the tree each walk has to visit.
    /// Single files stay on the cheap fixed interval; one `stat` costs nothing.
    static func progressPollingInterval(
        forEntryCount entries: Int,
        isDirectory: Bool
    ) -> Duration {
        guard isDirectory else { return .milliseconds(250) }
        return .seconds(max(1, min(8, entries / 1_000)))
    }

    private func localSize(of url: URL) -> Int64 {
        measureLocal(url).bytes
    }

    /// Exposed so the polling-cost benchmark measures the real walk.
    func benchmarkMeasureLocal(_ url: URL) -> (bytes: Int64, entries: Int) {
        measureLocal(url)
    }

    private func measureLocal(_ url: URL) -> (bytes: Int64, entries: Int) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return (0, 0)
        }
        if attributes[.type] as? FileAttributeType != .typeDirectory {
            return ((attributes[.size] as? NSNumber)?.int64Value ?? 0, 1)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return (0, 0)
        }
        var total: Int64 = 0
        var entries = 0
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { return (total, entries) }
            entries += 1
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let result = total.addingReportingOverflow(Int64(values.fileSize ?? 0))
            guard !result.overflow else { return (.max, entries) }
            total = result.partialValue
        }
        return (total, entries)
    }

    private func securePartialPermissions(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let permissions = url.hasDirectoryPath ? 0o700 : 0o600
        try? fileManager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func readUTF8String(
        at url: URL,
        maximumBytes: Int64
    ) -> (output: CapturedStandardOutput, exceededLimit: Bool) {
        guard let capture = readData(at: url, maximumBytes: maximumBytes) else {
            return (.unreadable, false)
        }
        guard let text = String(data: capture.data, encoding: .utf8) else {
            return (.invalidUTF8, capture.exceededLimit)
        }
        return (.text(text), capture.exceededLimit)
    }

    private static func readDiagnosticString(
        at url: URL,
        maximumBytes: Int64
    ) -> (text: String, exceededLimit: Bool) {
        guard let capture = readData(at: url, maximumBytes: maximumBytes) else {
            return ("", false)
        }
        return (
            String(decoding: capture.data, as: UTF8.self),
            capture.exceededLimit
        )
    }

    private static func readData(
        at url: URL,
        maximumBytes: Int64
    ) -> (data: Data, exceededLimit: Bool)? {
        guard
            maximumBytes > 0,
            maximumBytes <= Int64(Int.max),
            let handle = try? FileHandle(forReadingFrom: url)
        else {
            return nil
        }
        defer { try? handle.close() }
        do {
            let byteLimit = Int(maximumBytes)
            var data = Data()
            while data.count < byteLimit {
                let remaining = byteLimit - data.count
                guard
                    let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
                    !chunk.isEmpty
                else { break }
                data.append(chunk)
            }
            let exceededLimit: Bool
            if data.count == byteLimit {
                exceededLimit = try handle.read(upToCount: 1)?.isEmpty == false
            } else {
                exceededLimit = false
            }
            return (data, exceededLimit)
        } catch {
            return nil
        }
    }
}
