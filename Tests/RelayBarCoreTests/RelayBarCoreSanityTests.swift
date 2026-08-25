import XCTest
#if canImport(Darwin)
import Darwin.C
#else
import Glibc
#endif
@testable import RelayBarCore

/// Platform-portable checks for the engine the Linux tray reuses. These run
/// wherever RelayBarCore builds — macOS suites and the Linux CI job alike.
final class RelayBarCoreSanityTests: XCTestCase {
    func testMasterArgumentsMatchMacOSGrammar() throws {
        let tunnel = Tunnel(
            name: "web",
            sshHost: "bastion.example.com",
            additionalArguments: ["-v"],
            rules: [
                .localTCP(port: 8080, destinationHost: "10.0.0.5", destinationPort: 80)
            ]
        )
        XCTAssertTrue(tunnel.isSafeToRun)

        let arguments = SSHMasterInvocation.arguments(
            tunnel: tunnel,
            controlSocketPath: "/tmp/ctl/s"
        )

        XCTAssertEqual(arguments.prefix(4), ["-N", "-T", "-M", "-S"])
        XCTAssertEqual(arguments[4], "/tmp/ctl/s")
        // Enforced policy rides before user-visible forwarding flags.
        XCTAssertTrue(arguments.contains("ExitOnForwardFailure=yes"))
        XCTAssertEqual(arguments.suffix(2), ["-v", "bastion.example.com"])

        let forwardIndex = try XCTUnwrap(
            arguments.firstIndex(of: "-L"),
            "the local forward flag must be present"
        )
        XCTAssertEqual(
            arguments[arguments.index(after: forwardIndex)],
            "localhost:8080:10.0.0.5:80"
        )
    }

    func testUnsafeProfileIsRejected() {
        let tunnel = Tunnel(
            name: "bad host",
            sshHost: "-oProxyCommand=evil",
            rules: [.localTCP(port: 1, destinationHost: "h", destinationPort: 2)]
        )
        XCTAssertFalse(tunnel.isSafeToRun)
    }

    func testControlSocketPathBudgetMatchesOpenSSHNeeds() {
        // mux.c binds a `.XXXXXXXXXXXXXXXX` sibling before renaming; the
        // budget must leave room for that suffix plus the NUL terminator.
        XCTAssertEqual(
            SSHControlPath.maximumControlSocketPathByteCount,
            MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1 - 17
        )
    }

    func testRetryBackoffIsSharedAndCapped() {
        XCTAssertEqual(TunnelRetryPolicy.delay(for: 1), 1)
        XCTAssertEqual(TunnelRetryPolicy.delay(for: 4), 8)
        XCTAssertEqual(TunnelRetryPolicy.delay(for: 99), 60)
        XCTAssertEqual(TunnelRetryPolicy.defaultMaxAttempts, 10)
    }
}
