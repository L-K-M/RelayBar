import XCTest
import RelayBarCore
@testable import RelayBar

final class SSHCommandFormatterTests: XCTestCase {
    func testFormatsSingleLocalForwardWithExplicitLoopback() {
        let tunnel = Tunnel(
            name: "Web",
            localPort: 8_080,
            destinationHost: "localhost",
            destinationPort: 3_000,
            sshHost: "dev@example.com"
        )
        XCTAssertEqual(
            SSHCommandFormatter.command(for: tunnel),
            "ssh -N -T -L localhost:8080:localhost:3000 "
                + "-o StreamLocalBindMask=0177 dev@example.com"
        )
    }

    func testFormatsMixedRulesPolicyOptionsAndArguments() {
        let tunnel = Tunnel(
            name: "Mixed",
            sshHost: "bastion",
            additionalArguments: ["-p", "2222"],
            rules: [
                .localTCP(
                    bindAddress: "localhost",
                    port: 8_080,
                    destinationHost: "web.internal",
                    destinationPort: 80
                ),
                ForwardingRule(
                    kind: .localDynamic,
                    listen: .tcp(bindAddress: nil, port: 1_080)
                ),
                ForwardingRule(
                    kind: .remoteDynamic,
                    listen: .tcp(bindAddress: "0.0.0.0", port: 1_081)
                )
            ],
            reverseSOCKSPolicy: .allow(["api.example.com:443", "*.internal:8443"]),
            streamLocalSettings: StreamLocalSettings(
                bindMask: 0o077,
                unlinkStaleSocket: true
            )
        )
        XCTAssertEqual(
            SSHCommandFormatter.command(for: tunnel),
            "ssh -N -T -L localhost:8080:web.internal:80 -D localhost:1080 "
                + "-R 0.0.0.0:1081 "
                + "-o PermitRemoteOpen=api.example.com:443\\ \\*.internal:8443 "
                + "-o StreamLocalBindMask=0077 -o StreamLocalBindUnlink=yes "
                + "-p 2222 bastion"
        )
    }

    func testEscapesSpacesInUnixPathsAndHostnames() {
        let tunnel = Tunnel(
            name: "Sockets",
            sshHost: "builder mac",
            rules: [
                ForwardingRule(
                    kind: .local,
                    listen: .unix(path: "/tmp/my socket.sock"),
                    destination: .tcp(host: "localhost", port: 5_432)
                )
            ]
        )
        XCTAssertEqual(
            SSHCommandFormatter.command(for: tunnel),
            "ssh -N -T -L /tmp/my\\ socket.sock:localhost:5432 "
                + "-o StreamLocalBindMask=0177 builder\\ mac"
        )
    }

    func testEscapedQuotesAndSpacesRoundTripThroughQuickAdd() throws {
        let tunnel = Tunnel(
            name: "Odd",
            sshHost: "host",
            rules: [
                ForwardingRule(
                    kind: .local,
                    listen: .unix(path: "/tmp/it's here.sock"),
                    destination: .unix(path: "/tmp/dest.sock")
                )
            ]
        )
        let imported = try SSHCommandParser.parse(
            SSHCommandFormatter.command(for: tunnel)
        )
        XCTAssertEqual(imported.rules.count, 1)
        XCTAssertEqual(imported.rules[0].kind, tunnel.rules[0].kind)
        XCTAssertEqual(imported.rules[0].listen, tunnel.rules[0].listen)
        XCTAssertEqual(imported.rules[0].destination, tunnel.rules[0].destination)
    }

    func testFormattedCommandRoundTripsThroughQuickAdd() throws {
        let tunnel = Tunnel(
            name: "Round trip",
            sshHost: "dev@example.com",
            additionalArguments: ["-p", "2222", "-o", "ConnectTimeout=5"],
            rules: [
                .localTCP(
                    bindAddress: nil,
                    port: 8_080,
                    destinationHost: "web.internal",
                    destinationPort: 80
                ),
                ForwardingRule(
                    kind: .remote,
                    listen: .tcp(bindAddress: "localhost", port: 0),
                    destination: .tcp(host: "localhost", port: 4_321)
                ),
                ForwardingRule(
                    kind: .remoteDynamic,
                    listen: .tcp(bindAddress: "::1", port: 1_081)
                )
            ],
            reverseSOCKSPolicy: ReverseSOCKSPolicy.none
        )
        let imported = try SSHCommandParser.parse(
            SSHCommandFormatter.command(for: tunnel)
        )

        XCTAssertEqual(imported.sshHost, tunnel.sshHost)
        XCTAssertEqual(imported.additionalArguments, tunnel.additionalArguments)
        XCTAssertEqual(imported.reverseSOCKSPolicy, tunnel.reverseSOCKSPolicy)
        XCTAssertEqual(imported.rules.count, tunnel.rules.count)
        for (importedRule, originalRule) in zip(imported.rules, tunnel.rules) {
            XCTAssertEqual(importedRule.kind, originalRule.kind)
            // The formatter always names the bind explicitly; the importer
            // normalizes a bare port to localhost, so they agree.
            var normalizedRule = originalRule
            if
                normalizedRule.listen.kind == .tcp,
                normalizedRule.listen.tcp?.bindAddress == nil
            {
                normalizedRule.listen.tcp?.bindAddress = "localhost"
            }
            XCTAssertEqual(importedRule.listen, normalizedRule.listen)
            XCTAssertEqual(importedRule.destination, normalizedRule.destination)
        }
        // Formatting the re-import produces the identical command.
        var normalized = tunnel
        normalized.rules = imported.rules
        XCTAssertEqual(
            SSHCommandFormatter.command(for: normalized),
            SSHCommandFormatter.command(for: tunnel)
        )
    }
}
