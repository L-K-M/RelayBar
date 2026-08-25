import Darwin
import Foundation
import RelayBarCore

enum RemoteServerCatalogError: LocalizedError, Equatable {
    case invalidHost
    case invalidName
    case duplicateSavedHost
    case savedHostLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Enter a valid SSH host such as user@server."
        case .invalidName:
            return "The optional name is too long or contains unsupported characters."
        case .duplicateSavedHost:
            return "This SSH host is already saved in RelayBar."
        case .savedHostLimitReached:
            return "RelayBar can save up to 128 standalone SSH hosts."
        }
    }
}

enum SSHConfigHostReader {
    static let maximumFileSize = 1 * 1_024 * 1_024
    static let maximumHostCount = 256
    /// Include traversal stays cheap even for careless or hostile include
    /// chains: bounded depth, bounded file count, and visited-file cycles.
    static let maximumIncludeDepth = 8
    static let maximumIncludedFileCount = 64

    static func load(from url: URL) -> [String] {
        load(
            from: url,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func load(from url: URL, homeDirectory: URL) -> [String] {
        var state = LoadState()
        collect(
            from: url,
            homeDirectory: homeDirectory,
            depth: 0,
            state: &state
        )
        return state.hosts
    }

    static func parse(_ contents: String) -> [String] {
        var state = LoadState()
        appendHosts(
            from: contents,
            homeDirectory: nil,
            depth: 0,
            state: &state
        )
        return state.hosts
    }

    private struct LoadState {
        var hosts: [String] = []
        var seenHosts: Set<String> = []
        var visitedFiles: Set<String> = []
        var filesRead = 0
    }

    private static func collect(
        from url: URL,
        homeDirectory: URL,
        depth: Int,
        state: inout LoadState
    ) {
        guard
            depth <= maximumIncludeDepth,
            state.filesRead < maximumIncludedFileCount,
            state.hosts.count < maximumHostCount
        else {
            return
        }
        let fileKey = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard state.visitedFiles.insert(fileKey).inserted else { return }
        guard let contents = readBoundedString(from: url) else { return }
        state.filesRead += 1
        appendHosts(
            from: contents,
            homeDirectory: homeDirectory,
            depth: depth,
            state: &state
        )
    }

    private static func appendHosts(
        from contents: String,
        homeDirectory: URL?,
        depth: Int,
        state: inout LoadState
    ) {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            guard state.hosts.count < maximumHostCount else { return }
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count > 1 else { continue }

            if fields[0].caseInsensitiveCompare("Host") == .orderedSame {
                for rawHost in fields.dropFirst() {
                    let host = unquoted(rawHost)
                    guard
                        !host.hasPrefix("!"),
                        !host.contains(where: { "*?[".contains($0) }),
                        host.utf8.count <= 1_024,
                        SSHArgumentPolicy.isValidHostTarget(host)
                    else {
                        continue
                    }

                    let key = host.lowercased()
                    guard state.seenHosts.insert(key).inserted else { continue }
                    state.hosts.append(host)
                    if state.hosts.count == maximumHostCount { return }
                }
            } else if
                let homeDirectory,
                fields[0].caseInsensitiveCompare("Include") == .orderedSame
            {
                for rawPattern in fields.dropFirst() {
                    include(
                        pattern: unquoted(rawPattern),
                        homeDirectory: homeDirectory,
                        depth: depth,
                        state: &state
                    )
                }
            }
        }
    }

    /// OpenSSH resolves patterns without a leading slash or tilde against
    /// `~/.ssh` for user configuration files — the only kind RelayBar reads
    /// — and silently ignores patterns that match nothing. `~/` resolves
    /// against the same home directory the config came from, while `~user/`
    /// forms expand through `GLOB_TILDE`; `GLOB_MARK` suffixes directories
    /// so they can be skipped (OpenSSH includes files only), and
    /// `GLOB_BRACE` keeps brace patterns working as they do on macOS.
    private static func include(
        pattern: String,
        homeDirectory: URL,
        depth: Int,
        state: inout LoadState
    ) {
        let resolvedPattern: String
        if pattern.hasPrefix("~/") {
            resolvedPattern = homeDirectory
                .appendingPathComponent(String(pattern.dropFirst(2)))
                .path
        } else if pattern.hasPrefix("/") || pattern.hasPrefix("~") {
            resolvedPattern = pattern
        } else {
            resolvedPattern = homeDirectory
                .appendingPathComponent(".ssh", isDirectory: true)
                .appendingPathComponent(pattern)
                .path
        }

        var globResult = glob_t()
        let status = resolvedPattern.withCString {
            glob($0, GLOB_TILDE | GLOB_MARK | GLOB_BRACE, nil, &globResult)
        }
        defer { globfree(&globResult) }
        guard status == 0, let paths = globResult.gl_pathv else { return }
        for index in 0..<Int(globResult.gl_pathc) {
            guard let path = paths[index] else { continue }
            let match = String(cString: path)
            guard !match.hasSuffix("/") else { continue }
            collect(
                from: URL(fileURLWithPath: match),
                homeDirectory: homeDirectory,
                depth: depth + 1,
                state: &state
            )
        }
    }

    /// Reads regular files only: a glob can name a FIFO, device, or socket,
    /// and opening one of those for reading can block discovery forever.
    private static func readBoundedString(from url: URL) -> String? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path
            ),
            attributes[.type] as? FileAttributeType == .typeRegular
        else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        } catch {
            return nil
        }
        guard
            data.count <= maximumFileSize,
            let contents = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return contents
    }

    private static func unquoted(_ value: String) -> String {
        guard
            value.count >= 2,
            let first = value.first,
            let last = value.last,
            (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

@MainActor
final class RemoteServerCatalog {
    private struct Record: Codable {
        let id: UUID
        let name: String
        let sshHost: String
        let additionalArguments: [String]

        init(server: RemoteServer) {
            id = server.id
            name = server.name
            sshHost = server.sshHost
            additionalArguments = server.additionalArguments
        }

        func server(source: RemoteServer.Source) -> RemoteServer {
            RemoteServer(
                id: id,
                name: name,
                sshHost: sshHost,
                additionalArguments: additionalArguments,
                source: source
            )
        }

        var connectionIdentity: RemoteServer.ConnectionIdentity {
            RemoteServer.ConnectionIdentity(
                sshHost: sshHost,
                additionalArguments: additionalArguments
            )
        }
    }

    private struct LastPathRecord: Codable {
        let key: String
        let path: String
    }

    private static let savedLimit = 128
    private static let recentLimit = 8
    private static let lastPathLimit = 32
    private static let savedStorageKey = "remoteFiles.savedServers.v1"
    private static let recentStorageKey = "remoteFiles.recentServers.v1"
    private static let lastPathStorageKey = "remoteFiles.lastPaths.v1"

    private let defaults: UserDefaults?
    private let sshConfigURL: URL?
    private var savedRecords: [Record]
    private var recentRecords: [Record]
    private var lastPathRecords: [LastPathRecord]

    init(defaults: UserDefaults? = nil, sshConfigURL: URL? = nil) {
        self.defaults = defaults
        self.sshConfigURL = sshConfigURL
        savedRecords = Self.loadRecords(
            from: defaults,
            key: Self.savedStorageKey,
            limit: Self.savedLimit
        )
        recentRecords = Self.loadRecords(
            from: defaults,
            key: Self.recentStorageKey,
            limit: Self.recentLimit
        )
        lastPathRecords = Self.loadLastPaths(from: defaults)
    }

    static func appDefault() -> RemoteServerCatalog {
        RemoteServerCatalog(
            defaults: .standard,
            sshConfigURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ssh/config")
        )
    }

    func servers(from tunnels: [Tunnel]) -> [RemoteServer] {
        let recent = recentRecords.map { $0.server(source: .recent) }
        let saved = savedRecords
            .map { $0.server(source: .saved) }
            .sorted(by: Self.sortByDisplayName)
        let profiles = Self.profileServers(from: tunnels)
        let config = (sshConfigURL.map(SSHConfigHostReader.load) ?? [])
            .map {
                RemoteServer(
                    id: UUID(),
                    name: $0,
                    sshHost: $0,
                    additionalArguments: [],
                    source: .sshConfig
                )
            }
            .sorted(by: Self.sortByDisplayName)

        var result: [RemoteServer] = []
        var seen: Set<RemoteServer.ConnectionIdentity> = []
        for server in recent + saved + profiles + config {
            guard seen.insert(server.connectionIdentity).inserted else { continue }
            result.append(server)
        }
        return result
    }

    func add(name: String, sshHost: String) throws -> RemoteServer {
        let normalizedHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            normalizedHost.utf8.count <= 1_024,
            SSHArgumentPolicy.isValidHostTarget(normalizedHost)
        else {
            throw RemoteServerCatalogError.invalidHost
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            normalizedName.utf8.count <= 256,
            !normalizedName.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
                    || CharacterSet.newlines.contains($0)
            })
        else {
            throw RemoteServerCatalogError.invalidName
        }

        let server = RemoteServer(
            id: UUID(),
            name: normalizedName.isEmpty ? normalizedHost : normalizedName,
            sshHost: normalizedHost,
            additionalArguments: [],
            source: .saved
        )
        guard
            !savedRecords.contains(where: {
                $0.connectionIdentity == server.connectionIdentity
            })
        else {
            throw RemoteServerCatalogError.duplicateSavedHost
        }
        guard savedRecords.count < Self.savedLimit else {
            throw RemoteServerCatalogError.savedHostLimitReached
        }

        savedRecords.append(Record(server: server))
        persist(savedRecords, key: Self.savedStorageKey)
        return server
    }

    func isSavedServer(id: UUID) -> Bool {
        savedRecords.contains { $0.id == id }
    }

    func removeSavedServer(id: UUID) {
        guard let removed = savedRecords.first(where: { $0.id == id }) else { return }
        savedRecords.removeAll { $0.id == id }
        recentRecords.removeAll {
            $0.connectionIdentity == removed.connectionIdentity
        }
        persist(savedRecords, key: Self.savedStorageKey)
        persist(recentRecords, key: Self.recentStorageKey)
    }

    /// The last successfully opened remote path for this exact connection,
    /// so the launcher can offer to continue where the user left off instead
    /// of resetting to an empty field on every window.
    func lastOpenedPath(for server: RemoteServer) -> String? {
        let key = Self.lastPathKey(for: server.connectionIdentity)
        return lastPathRecords.first { $0.key == key }?.path
    }

    func recordLastOpenedPath(_ path: String, for server: RemoteServer) {
        let normalized = RemotePath.normalized(path)
        guard RemotePath.validationMessage(for: normalized) == nil else { return }
        let key = Self.lastPathKey(for: server.connectionIdentity)
        if lastPathRecords.first?.key == key,
           lastPathRecords.first?.path == normalized {
            return
        }
        lastPathRecords.removeAll { $0.key == key }
        lastPathRecords.insert(
            LastPathRecord(key: key, path: normalized),
            at: 0
        )
        if lastPathRecords.count > Self.lastPathLimit {
            lastPathRecords.removeLast(lastPathRecords.count - Self.lastPathLimit)
        }
        persist(lastPathRecords, key: Self.lastPathStorageKey)
    }

    /// Newlines cannot appear in a validated host or option value, so one
    /// key line per component is unambiguous.
    private static func lastPathKey(
        for identity: RemoteServer.ConnectionIdentity
    ) -> String {
        ([identity.sshHost] + identity.additionalArguments)
            .joined(separator: "\n")
    }

    private static func loadLastPaths(
        from defaults: UserDefaults?
    ) -> [LastPathRecord] {
        guard
            let data = defaults?.data(forKey: lastPathStorageKey),
            let decoded = try? JSONDecoder().decode(
                [LastPathRecord].self,
                from: data
            )
        else {
            return []
        }
        var result: [LastPathRecord] = []
        var seen: Set<String> = []
        for record in decoded.prefix(lastPathLimit) {
            guard
                !record.key.isEmpty,
                RemotePath.validationMessage(for: record.path) == nil,
                seen.insert(record.key).inserted
            else {
                continue
            }
            result.append(record)
        }
        return result
    }

    func recordSuccessfulOpen(_ server: RemoteServer) {
        if recentRecords.first?.connectionIdentity == server.connectionIdentity {
            return
        }
        recentRecords.removeAll {
            $0.connectionIdentity == server.connectionIdentity
        }
        recentRecords.insert(Record(server: server), at: 0)
        if recentRecords.count > Self.recentLimit {
            recentRecords.removeLast(recentRecords.count - Self.recentLimit)
        }
        persist(recentRecords, key: Self.recentStorageKey)
    }

    private func persist<Records: Encodable>(_ records: [Records], key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadRecords(
        from defaults: UserDefaults?,
        key: String,
        limit: Int
    ) -> [Record] {
        guard
            let data = defaults?.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Record].self, from: data)
        else {
            return []
        }

        var result: [Record] = []
        var seen: Set<RemoteServer.ConnectionIdentity> = []
        for record in decoded.prefix(limit) {
            guard
                !record.name.isEmpty,
                record.name.utf8.count <= 256,
                !record.name.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0)
                        || CharacterSet.newlines.contains($0)
                }),
                record.sshHost.utf8.count <= 1_024,
                SSHArgumentPolicy.isValidHostTarget(record.sshHost),
                SSHArgumentPolicy.areAdditionalArgumentsSafe(record.additionalArguments),
                seen.insert(record.connectionIdentity).inserted
            else {
                continue
            }
            result.append(record)
        }
        return result
    }

    private static func profileServers(from tunnels: [Tunnel]) -> [RemoteServer] {
        var serversByConnection: [RemoteServer.ConnectionIdentity: RemoteServer] = [:]
        var duplicateConnections: Set<RemoteServer.ConnectionIdentity> = []

        for tunnel in tunnels {
            let server = RemoteServer(tunnel: tunnel)
            if serversByConnection[server.connectionIdentity] == nil {
                serversByConnection[server.connectionIdentity] = server
            } else {
                duplicateConnections.insert(server.connectionIdentity)
            }
        }

        return serversByConnection.map { identity, server in
            guard duplicateConnections.contains(identity) else { return server }
            return RemoteServer(
                id: server.id,
                name: server.sshHost,
                sshHost: server.sshHost,
                additionalArguments: server.additionalArguments,
                source: .forwardingProfile
            )
        }
        .sorted(by: sortByDisplayName)
    }

    private static func sortByDisplayName(_ lhs: RemoteServer, _ rhs: RemoteServer) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}
