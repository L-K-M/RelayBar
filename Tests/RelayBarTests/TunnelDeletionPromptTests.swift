import XCTest
@testable import RelayBar

final class TunnelDeletionPromptTests: XCTestCase {
    func testStoppedProfilePromptIdentifiesProfileRouteAndHost() {
        let tunnel = Tunnel(
            name: "Admin",
            localPort: 8_080,
            destinationHost: "dashboard.internal",
            destinationPort: 443,
            sshHost: "bastion.example"
        )

        let prompt = TunnelDeletionPrompt(
            tunnel: tunnel,
            phase: .stopped,
            runtimePorts: [:]
        )

        XCTAssertEqual(prompt.title, "Delete \u{201c}Admin\u{201d}?")
        XCTAssertTrue(prompt.message.contains("SSH host: bastion.example"))
        XCTAssertTrue(
            prompt.message.contains(tunnel.displaySummary(runtimePorts: [:]))
        )
        XCTAssertTrue(prompt.message.contains("permanently removes the profile"))
        XCTAssertFalse(prompt.message.contains("stops its active SSH connection"))
    }

    func testConnectionWarningMatchesLifecycleActivityForEveryPhase() {
        let tunnel = Tunnel(
            name: "Database",
            localPort: 5_432,
            destinationHost: "database.internal",
            destinationPort: 5_432,
            sshHost: "production-bastion"
        )

        // Keep this list exhaustive with TunnelPhase so a new lifecycle case
        // must make an explicit prompt-copy decision here.
        let phases: [TunnelPhase] = [
            .stopped,
            .starting,
            .retrying(attempt: 1, maxAttempts: 3, delay: 2, message: "retry"),
            .running,
            .failed("failed")
        ]

        for phase in phases {
            let prompt = TunnelDeletionPrompt(
                tunnel: tunnel,
                phase: phase,
                runtimePorts: [:]
            )

            XCTAssertEqual(
                prompt.message.contains("stops its active SSH connection"),
                phase.isLifecycleActive,
                "Connection warning did not match lifecycle activity for \(phase)"
            )
        }
    }
}
