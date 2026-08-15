import Darwin
import Foundation

struct SSHControlLocations: Sendable {
    let directory: URL
    let socket: URL
}

enum SSHControlPathError: LocalizedError, Equatable {
    case directoryCreationFailed
    case pathTooLong

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            "RelayBar could not create a private SSH control directory."
        case .pathTooLong:
            "The private SSH control path is too long for macOS."
        }
    }
}

enum SSHControlPath {
    static let privateDirectoryPrefix = "RelayBar-SSH."
    static let controlSocketName = "s"
    static let openSSHBindTemporarySuffixByteCount = 17
    static let unixSocketPathByteCapacity = MemoryLayout.size(
        ofValue: sockaddr_un().sun_path
    )
    static let maximumControlSocketPathByteCount =
        unixSocketPathByteCapacity
        - 1 // NUL terminator
        - openSSHBindTemporarySuffixByteCount

    static func create(
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
            return Darwin.mkdtemp(baseAddress) != nil
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
        // within Darwin's sockaddr_un.sun_path.
        guard socket.path.utf8.count <= maximumControlSocketPathByteCount else {
            try? fileManager.removeItem(at: directory)
            throw SSHControlPathError.pathTooLong
        }
        return SSHControlLocations(directory: directory, socket: socket)
    }
}
