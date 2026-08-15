import XCTest
@testable import RelayBar

final class QuitConfirmationTests: XCTestCase {
    func testHeadlineIsPinned() {
        XCTAssertEqual(QuitConfirmation.messageText, "Quit RelayBar?")
        XCTAssertEqual(QuitConfirmation.cancelButtonTitle, "Cancel")
    }

    func testSingularCopyForOneActiveTunnel() {
        XCTAssertEqual(
            QuitConfirmation.informativeText(activeTunnelCount: 1),
            "1 tunnel is running. Quitting stops it."
        )
        XCTAssertEqual(
            QuitConfirmation.stopButtonTitle(activeTunnelCount: 1),
            "Stop Tunnel and Quit"
        )
    }

    func testPluralCopyForSeveralActiveTunnels() {
        XCTAssertEqual(
            QuitConfirmation.informativeText(activeTunnelCount: 3),
            "3 tunnels are running. Quitting stops them."
        )
        XCTAssertEqual(
            QuitConfirmation.stopButtonTitle(activeTunnelCount: 3),
            "Stop Tunnels and Quit"
        )
        XCTAssertEqual(
            QuitConfirmation.stopButtonTitle(activeTunnelCount: 2),
            "Stop Tunnels and Quit"
        )
    }
}
