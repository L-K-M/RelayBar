import Foundation
import XCTest
import RelayBarCore
@testable import RelayBar

final class SSHMasterPolicyTests: XCTestCase {
    func testBothMasterBuildersApplyEachEnforcedOptionExactlyOnce() throws {
        let socket = URL(fileURLWithPath: "/tmp/relaybar-master-policy/socket")
        let connectionArguments = [
            "-p", "2207",
            "-l", "cli-user",
            "-J", "jump.example.test",
            "-i", "/tmp/relaybar-test-identity",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        let tunnel = Tunnel(
            name: "Policy",
            localPort: 43_210,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: "guarded-master",
            additionalArguments: connectionArguments
        )
        let server = RemoteServer(
            id: UUID(),
            name: "Policy",
            sshHost: "guarded-master",
            additionalArguments: connectionArguments
        )

        let masters = [
            TunnelStore.masterArguments(
                tunnel: tunnel,
                controlSocket: socket
            ),
            try RemoteFileSSHSession.masterArguments(
                for: server,
                controlSocket: socket
            )
        ]

        for arguments in masters {
            for flag in ["-N", "-T", "-M"] {
                XCTAssertEqual(
                    arguments.filter { $0 == flag }.count,
                    1,
                    "Expected one forced flag for \(flag): \(arguments)"
                )
            }
            for option in SSHMasterPolicy.enforcedOptions {
                XCTAssertEqual(
                    arguments.filter { $0 == option }.count,
                    1,
                    "Expected one forced value for \(option): \(arguments)"
                )
                XCTAssertTrue(
                    arguments.containsSubsequence(["-o", option]),
                    "Expected -o immediately before \(option): \(arguments)"
                )
            }
            XCTAssertTrue(arguments.containsSubsequence(["-J", "jump.example.test"]))
            XCTAssertTrue(
                arguments.containsSubsequence([
                    "-i", "/tmp/relaybar-test-identity"
                ])
            )
            XCTAssertTrue(
                arguments.containsSubsequence([
                    "-o", "StrictHostKeyChecking=accept-new"
                ])
            )
            XCTAssertEqual(arguments.last, "guarded-master")
        }
    }

    func testRealOpenSSHEvaluationCannotOverrideMasterPolicy() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/ssh")
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: executable.path),
            "/usr/bin/ssh is required for configuration evaluation."
        )
        let socket = URL(fileURLWithPath: "/tmp/relaybar-master-policy/socket")
        let tunnel = Tunnel(
            name: "Policy",
            localPort: 43_210,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: "guarded-master"
        )
        let server = RemoteServer(
            id: UUID(),
            name: "Policy",
            sshHost: "guarded-master",
            additionalArguments: []
        )
        let masters = [
            TunnelStore.masterArguments(
                tunnel: tunnel,
                controlSocket: socket
            ),
            try RemoteFileSSHSession.masterArguments(
                for: server,
                controlSocket: socket
            )
        ]

        for arguments in masters {
            let configuration = try evaluatedConfiguration(
                executable: executable,
                masterArguments: arguments
            )

            XCTAssertEqual(configuration["forkafterauthentication"], ["no"])
            XCTAssertEqual(configuration["permitlocalcommand"], ["no"])
            XCTAssertEqual(configuration["tunnel"], ["false"])
            XCTAssertEqual(configuration["gatewayports"], ["no"])
            XCTAssertEqual(configuration["forwardagent"], ["no"])
            XCTAssertEqual(configuration["forwardx11"], ["no"])
            XCTAssertEqual(configuration["forwardx11trusted"], ["no"])
            XCTAssertEqual(configuration["controlmaster"], ["true"])
            XCTAssertEqual(configuration["controlpersist"], ["no"])
            XCTAssertEqual(configuration["clearallforwardings"], ["yes"])
            XCTAssertEqual(configuration["batchmode"], ["yes"])
            XCTAssertEqual(configuration["connecttimeout"], ["10"])
            XCTAssertEqual(configuration["exitonforwardfailure"], ["yes"])
            XCTAssertEqual(configuration["serveraliveinterval"], ["30"])
            XCTAssertEqual(configuration["serveralivecountmax"], ["3"])
            XCTAssertEqual(configuration["requesttty"], ["false"])
            XCTAssertEqual(configuration["sessiontype"], ["none"])

            XCTAssertEqual(configuration["hostname"], ["target.example.test"])
            XCTAssertEqual(configuration["user"], ["config-user"])
            XCTAssertEqual(configuration["port"], ["2207"])
            XCTAssertEqual(
                configuration["identityfile"],
                ["/tmp/relaybar-test-identity"]
            )
            XCTAssertEqual(
                configuration["identityagent"],
                ["/tmp/relaybar-test-agent.sock"]
            )
            XCTAssertEqual(
                configuration["userknownhostsfile"],
                ["/tmp/relaybar-test-known-hosts"]
            )
            XCTAssertEqual(configuration["stricthostkeychecking"], ["accept-new"])
            XCTAssertEqual(configuration["proxyjump"], ["jump.example.test"])
        }
    }

    private func evaluatedConfiguration(
        executable: URL,
        masterArguments: [String]
    ) throws -> [String: [String]] {
        let process = Process()
        // One pipe cannot deadlock while the parent drains it to EOF. Separate
        // stdout and stderr pipes would require concurrent readers if either
        // stream ever grew to the kernel pipe-buffer limit.
        let response = Pipe()
        process.executableURL = executable
        process.arguments = [
            "-G",
            "-F", hostileConfigurationURL.path
        ] + masterArguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = response
        process.standardError = response

        try process.run()
        let responseData = response.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let responseText = String(decoding: responseData, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, responseText)

        var configuration: [String: [String]] = [:]
        for line in responseText.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { continue }
            configuration[String(fields[0]), default: []].append(String(fields[1]))
        }
        return configuration
    }

    private var hostileConfigurationURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hostile-master-ssh-config")
    }
}

private extension Array where Element: Equatable {
    func containsSubsequence(_ subsequence: [Element]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else {
            return false
        }
        for start in 0...(count - subsequence.count) where
            Array(self[start..<(start + subsequence.count)]) == subsequence
        {
            return true
        }
        return false
    }
}
