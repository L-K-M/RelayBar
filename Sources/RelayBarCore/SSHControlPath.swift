#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

public struct SSHControlLocations: Sendable {
    public let directory: URL
    public let socket: URL

    public init(directory: URL, socket: URL) {
        self.directory = directory
        self.socket = socket
    }
}

public enum SSHControlPathError: LocalizedError, Equatable {
    case directoryCreationFailed
    case pathTooLong

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            "RelayBar could not create a private SSH control directory."
        case .pathTooLong:
            "The private SSH control path is too long."
        }
    }
}

public enum SSHControlPath {
    public static let privateDirectoryPrefix = "RelayBar-SSH."
    public static let controlSocketName = "s"
    public static let openSSHBindTemporarySuffixByteCount = 17
    public static let unixSocketPathByteCapacity = MemoryLayout.size(
        ofValue: sockaddr_un().sun_path
    )
    public static let maximumControlSocketPathByteCount =
        unixSocketPathByteCapacity
        - 1 // NUL terminator
        - openSSHBindTemporarySuffixByteCount

    public static func create(
        in temporaryDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> SSHControlLocations {
        let templateURL = temporaryDirectory.appendingPathComponent(
            "\(privateDirectoryPrefix)XXXXXXXX",
            isDirectory: true
        )
        var template = Array(templateURL.path.utf8CString)
        let didCreateDirectory = template.withUnsafeMutableBufferPointer {
            buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            // mkdtemp exists on both Darwin and Glibc with the same contract.
            return mkdtemp(baseAddress) != nil
        }
        guard didCreateDirectory else {
            throw SSHControlPathError.directoryCreationFailed
        }

        let directoryPath = template.withUnsafeBufferPointer { buffer in
            String(cString: buffer.baseAddress!)
        }
        let directory = URL(
            fileURLWithPath: directoryPath,
            isDirectory: true
        )
        let socket = directory.appendingPathComponent(controlSocketName)

        // OpenSSH's mux listener first binds a sibling path using the
        // `.XXXXXXXXXXXXXXXX` suffix from mux.c, then renames it to the final
        // ControlPath. Both that suffix and the terminating NUL must fit
        // within sockaddr_un.sun_path.
        guard socket.path.utf8.count <= maximumControlSocketPathByteCount else {
            try? fileManager.removeItem(at: directory)
            throw SSHControlPathError.pathTooLong
        }
        return SSHControlLocations(directory: directory, socket: socket)
    }
}
