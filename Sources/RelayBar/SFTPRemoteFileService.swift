import Darwin
import Foundation

protocol RemoteFileServing: AnyObject, Sendable {
    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry]
    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws
    func preparePreview(server: RemoteServer, entry: RemoteFileEntry) async throws -> URL
}

/// Configuration is immutable after initialization. Each command owns separate
/// process state, and the small boxes shared with callbacks synchronize access.
final class SFTPRemoteFileService: RemoteFileServing, @unchecked Sendable {
    private struct CommandResult {
        let status: Int32
        let output: String
        let error: String
        let exceededOutputLimit: Bool
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancellationRequested = false
        private var forceStopScheduled = false

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        var shouldStart: Bool {
            lock.lock()
            defer { lock.unlock() }
            return !cancellationRequested
        }

        func clear() {
            lock.lock()
            process = nil
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            cancellationRequested = true
            let current = process
            lock.unlock()

            guard let current, current.isRunning else { return }
            lock.lock()
            let shouldScheduleForceStop = !forceStopScheduled
            forceStopScheduled = true
            lock.unlock()
            current.terminate()
            if shouldScheduleForceStop {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if current.isRunning {
                        Darwin.kill(current.processIdentifier, SIGKILL)
                    }
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

    private let executableURL: URL
    private let fileManager: FileManager
    private let previewSizeLimit: Int64
    private let markdownPreviewSizeLimit: Int64
    private let standardOutputLimit: Int64
    private let standardErrorLimit: Int64

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/sftp"),
        fileManager: FileManager = .default,
        previewSizeLimit: Int64 = 100 * 1_024 * 1_024,
        markdownPreviewSizeLimit: Int64 = Int64(RemoteMarkdownDecoder.maximumByteCount),
        standardOutputLimit: Int64 = 32 * 1_024 * 1_024,
        standardErrorLimit: Int64 = 1 * 1_024 * 1_024
    ) {
        self.executableURL = executableURL
        self.fileManager = fileManager
        self.previewSizeLimit = previewSizeLimit
        self.markdownPreviewSizeLimit = markdownPreviewSizeLimit
        self.standardOutputLimit = standardOutputLimit
        self.standardErrorLimit = standardErrorLimit
    }

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        guard RemotePath.validationMessage(for: path) == nil else {
            throw RemoteFileError.invalidPath
        }
        let normalizedPath = RemotePath.normalized(path)
        let result = try await run(
            server: server,
            batchInput: SFTPCommandBuilder.listCommand(path: normalizedPath)
        )
        try validate(result)
        return try SFTPListingParser.parse(result.output, parentPath: normalizedPath)
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

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: partial,
                    backupItemName: nil
                )
            } else {
                try fileManager.moveItem(at: partial, to: destination)
            }
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

    private func runTransfer(
        server: RemoteServer,
        batchInput: String,
        partialURL: URL,
        maximumBytes: Int64?,
        limitError: RemoteFileError,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            let pollingInterval: Duration = partialURL.hasDirectoryPath
                ? .seconds(1)
                : .milliseconds(250)
            group.addTask { [self] in
                let result = try await run(server: server, batchInput: batchInput)
                try validate(result)
                return true
            }
            group.addTask { [self] in
                while !Task.isCancelled {
                    securePartialPermissions(at: partialURL)
                    let completedBytes = localSize(of: partialURL)
                    progress(completedBytes)
                    if let maximumBytes, completedBytes > maximumBytes {
                        throw limitError
                    }
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

    private func run(server: RemoteServer, batchInput: String) async throws -> CommandResult {
        let arguments = try SFTPCommandBuilder.processArguments(for: server)
        let processBox = ProcessBox()
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

                    let outputHandle = try FileHandle(forWritingTo: outputURL)
                    let errorHandle = try FileHandle(forWritingTo: errorURL)
                    let inputPipe = Pipe()
                    let process = Process()
                    let outputMonitor = DispatchSource.makeTimerSource(
                        queue: DispatchQueue(label: "RelayBar.SFTPOutputLimit")
                    )
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardInput = inputPipe
                    process.standardOutput = outputHandle
                    process.standardError = errorHandle
                    processBox.set(process)

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

                    process.terminationHandler = { finished in
                        outputMonitor.cancel()
                        outputHandle.closeFile()
                        errorHandle.closeFile()
                        if
                            Self.fileSize(at: outputURL) > outputLimit
                                || Self.fileSize(at: errorURL) > errorLimit
                        {
                            outputLimitBox.markExceeded()
                        }
                        let output = Self.readString(
                            at: outputURL,
                            maximumBytes: outputLimit
                        )
                        let error = Self.readString(
                            at: errorURL,
                            maximumBytes: errorLimit
                        )
                        try? FileManager.default.removeItem(at: temporaryDirectory)
                        processBox.clear()
                        continuation.resume(
                            returning: CommandResult(
                                status: finished.terminationStatus,
                                output: output,
                                error: error,
                                exceededOutputLimit: outputLimitBox.hasExceeded
                            )
                        )
                    }

                    do {
                        outputMonitor.resume()
                        guard processBox.shouldStart else {
                            throw CancellationError()
                        }
                        try process.run()
                    } catch {
                        outputMonitor.cancel()
                        outputHandle.closeFile()
                        errorHandle.closeFile()
                        try? fileManager.removeItem(at: temporaryDirectory)
                        processBox.clear()
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
                    processBox.clear()
                    continuation.resume(throwing: error)
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            processBox.cancel()
        }
    }

    private func validate(_ result: CommandResult) throws {
        if result.exceededOutputLimit {
            throw RemoteFileError.responseTooLarge
        }
        guard result.status == 0 else {
            throw RemoteFileError.commandFailed(friendlyMessage(from: result.error))
        }
    }

    private func friendlyMessage(from errorOutput: String) -> String {
        let lines = errorOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("sftp>") }
        let rawDetail = lines.suffix(2).joined(separator: " ")
        let safeScalars = rawDetail.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let detail = String(String.UnicodeScalarView(safeScalars).prefix(512))

        if detail.localizedCaseInsensitiveContains("permission denied") {
            return "Permission was denied for this server or path."
        }
        if detail.localizedCaseInsensitiveContains("host key verification failed") {
            return "SSH could not verify this server's host key."
        }
        if
            detail.localizedCaseInsensitiveContains("no such file")
                || detail.localizedCaseInsensitiveContains("not found")
        {
            return "The remote path wasn’t found."
        }
        if detail.localizedCaseInsensitiveContains("could not resolve hostname") {
            return "The saved server could not be found."
        }
        if
            detail.localizedCaseInsensitiveContains("operation timed out")
                || detail.localizedCaseInsensitiveContains("connection timed out")
        {
            return "The connection timed out."
        }
        if detail.localizedCaseInsensitiveContains("connection refused") {
            return "The server refused the connection."
        }
        if
            detail.localizedCaseInsensitiveContains("connection closed")
                || detail.localizedCaseInsensitiveContains("connection reset")
        {
            return "The connection was lost."
        }
        return detail.isEmpty ? "The remote operation failed." : detail
    }

    private func localSize(of url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return 0
        }
        if attributes[.type] as? FileAttributeType != .typeDirectory {
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { return total }
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else { continue }
            let result = total.addingReportingOverflow(Int64(values.fileSize ?? 0))
            guard !result.overflow else { return .max }
            total = result.partialValue
        }
        return total
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

    private static func readString(at url: URL, maximumBytes: Int64) -> String {
        guard
            maximumBytes > 0,
            maximumBytes <= Int64(Int.max),
            let handle = try? FileHandle(forReadingFrom: url)
        else {
            return ""
        }
        defer { try? handle.close() }
        do {
            guard let data = try handle.read(upToCount: Int(maximumBytes)) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
