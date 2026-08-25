import XCTest
import RelayBarCore
@testable import RelayBar

/// Task 047. The editor names the first blocking issue instead of disabling
/// Save without explanation; the draft's reasons must stay aligned with what
/// `forwardingRule` actually rejects.
final class ForwardingRuleDraftValidationTests: XCTestCase {
    func testBlankDraftAsksForAListenPort() {
        let draft = ForwardingRuleDraft(kind: .local)
        XCTAssertEqual(draft.validationIssue, "enter a listen port")
    }

    func testNonNumericAndOutOfRangeListenPorts() {
        var draft = ForwardingRuleDraft(kind: .local)
        draft.listenPort = "abc"
        XCTAssertEqual(draft.validationIssue, "the listen port is not a number")

        draft.listenPort = "0"
        XCTAssertEqual(draft.validationIssue, "the listen port must be 1–65535")

        draft.listenPort = "70000"
        XCTAssertEqual(draft.validationIssue, "the listen port must be 1–65535")

        draft.kind = .remote
        draft.listenPort = "0"
        draft.destinationHost = "localhost"
        XCTAssertEqual(
            draft.validationIssue,
            "enter a destination port",
            "Port 0 is valid for remote listeners, so the first issue moves on."
        )
    }

    func testListenAddressRejectsWhitespace() {
        var draft = ForwardingRuleDraft(kind: .local)
        draft.listenPort = "8080"
        draft.destinationPort = "3000"
        draft.listenAddress = "bad host"
        XCTAssertEqual(
            draft.validationIssue,
            "the listen address cannot contain spaces or start with a dash"
        )
    }

    func testUnixListenRequiresAbsolutePathWithoutColon() {
        var draft = ForwardingRuleDraft(kind: .local)
        draft.listenKind = .unix
        draft.listenPort = ""
        XCTAssertEqual(draft.validationIssue, "enter a local socket path")

        draft.listenPath = "relative.sock"
        XCTAssertEqual(
            draft.validationIssue,
            "the socket path must be absolute and cannot contain a colon"
        )

        draft.listenPath = "/tmp/ok.sock"
        draft.destinationKind = .tcp
        draft.destinationHost = "localhost"
        draft.destinationPort = "80"
        XCTAssertNil(draft.validationIssue)
    }

    func testDestinationChecksSkipDynamicKinds() {
        var draft = ForwardingRuleDraft(kind: .localDynamic)
        draft.listenPort = "1080"
        draft.destinationHost = ""
        draft.destinationPort = ""
        XCTAssertNil(
            draft.validationIssue,
            "SOCKS rules have no destination to validate."
        )

        let fixed = ForwardingRuleDraft(kind: .local)
        XCTAssertEqual(fixed.validationIssue, "enter a listen port")
    }

    func testDestinationValidation() {
        var draft = ForwardingRuleDraft(kind: .local)
        draft.listenPort = "8080"
        draft.destinationHost = ""
        XCTAssertEqual(draft.validationIssue, "enter a destination host")

        draft.destinationHost = "localhost"
        draft.destinationPort = ""
        XCTAssertEqual(draft.validationIssue, "enter a destination port")

        draft.destinationPort = "0"
        XCTAssertEqual(draft.validationIssue, "the destination port must be 1–65535")

        draft.destinationPort = "3000"
        XCTAssertNil(draft.validationIssue)
        XCTAssertNotNil(draft.forwardingRule)
    }

    /// The issue text and the hard gate must agree: any draft with no issue
    /// builds a valid rule, and any draft with an issue does not.
    func testIssueAndForwardingRuleGateAgree() {
        var valid = ForwardingRuleDraft(kind: .local)
        valid.listenPort = "8080"
        valid.destinationHost = "localhost"
        valid.destinationPort = "3000"
        XCTAssertEqual(valid.validationIssue, nil)
        XCTAssertNotNil(valid.forwardingRule)

        var invalid = ForwardingRuleDraft(kind: .remote)
        invalid.listenPort = "99999"
        invalid.destinationHost = "localhost"
        invalid.destinationPort = "80"
        XCTAssertNotNil(invalid.validationIssue)
        XCTAssertNil(invalid.forwardingRule)
    }

    // MARK: Editor-level mirror

    private func validRule() -> ForwardingRuleDraft {
        var draft = ForwardingRuleDraft(kind: .local)
        draft.listenPort = "8080"
        draft.destinationHost = "localhost"
        draft.destinationPort = "3000"
        return draft
    }

    private func issue(
        hasPendingGroupName: Bool = false,
        rules: [ForwardingRuleDraft],
        streamBindMask: String = "0177",
        reversePolicyChoice: ReversePolicyChoice = .unspecified,
        hasReverseSOCKS: Bool = false,
        reverseAllowedDestinations: String = "",
        sshHost: String = "dev@example.com"
    ) -> String? {
        TunnelEditorValidation.firstIssue(
            hasPendingGroupName: hasPendingGroupName,
            rules: rules,
            streamBindMask: streamBindMask,
            reversePolicyChoice: reversePolicyChoice,
            hasReverseSOCKS: hasReverseSOCKS,
            reverseAllowedDestinations: reverseAllowedDestinations,
            sshHost: sshHost
        )
    }

    /// Task 047. The editor-level mirror stops at the first problem in
    /// builtTunnel's order and stays silent for a fully valid form.
    func testEditorLevelIssuesCoverEveryGateRejection() {
        XCTAssertEqual(
            issue(hasPendingGroupName: true, rules: [validRule()]),
            "Finish naming the new group."
        )
        XCTAssertEqual(issue(rules: []), "Add at least one forwarding rule.")
        XCTAssertEqual(
            issue(rules: [validRule()], streamBindMask: "999"),
            "Enter a valid octal socket bind mask such as 0177."
        )
        XCTAssertEqual(
            issue(
                rules: [validRule()],
                reversePolicyChoice: .unspecified,
                hasReverseSOCKS: true
            ),
            "Choose a destination policy for Remote SOCKS."
        )
        XCTAssertEqual(
            issue(
                rules: [validRule()],
                reversePolicyChoice: .restricted,
                hasReverseSOCKS: true,
                reverseAllowedDestinations: "not-a-host:port"
            ),
            "Allowed destinations must be host:port entries."
        )
        XCTAssertEqual(
            issue(rules: [validRule()], sshHost: "  "),
            "Enter an SSH host such as user@server."
        )
        XCTAssertEqual(
            issue(rules: [validRule()], sshHost: "bad host"),
            "The SSH host cannot contain spaces or start with a dash."
        )
        XCTAssertNil(
            issue(rules: [validRule()]),
            "A valid form names no blocking issue."
        )
    }

    /// Task 047. Conflicting listeners are named before the mirror runs out
    /// of specific reasons.
    func testEditorLevelMirrorNamesConflictingListeners() {
        var first = validRule()
        first.listenAddress = "localhost"
        var second = validRule()
        second.listenAddress = "127.0.0.1"
        XCTAssertEqual(
            issue(rules: [first, second]),
            "Two rules listen on the same address and port."
        )
    }

    /// Task 047. A restricted allowlist with only valid entries passes the
    /// editor-level mirror.
    func testEditorLevelMirrorAcceptsValidReverseAllowlist() {
        XCTAssertNil(
            issue(
                rules: [validRule()],
                reversePolicyChoice: .restricted,
                hasReverseSOCKS: true,
                reverseAllowedDestinations: "api.example.com:443\n*.internal:8443"
            )
        )
    }
}
