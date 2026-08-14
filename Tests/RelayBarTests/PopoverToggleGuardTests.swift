import AppKit
import XCTest
@testable import RelayBar

final class PopoverToggleGuardTests: XCTestCase {
    func testTogglePresentsWhenNoCloseWasRecorded() {
        var toggleGuard = PopoverToggleGuard()
        XCTAssertTrue(toggleGuard.shouldPresent(now: 1_000))
    }

    func testToggleInsideTheSuppressionWindowIsSwallowedOnce() {
        var toggleGuard = PopoverToggleGuard()
        toggleGuard.recordClose(uptime: 1_000)

        XCTAssertFalse(
            toggleGuard.shouldPresent(
                now: 1_000 + PopoverToggleGuard.suppressionWindow / 2
            ),
            "The action half of the click that closed the popover must not reopen it."
        )
        XCTAssertTrue(
            toggleGuard.shouldPresent(
                now: 1_000 + PopoverToggleGuard.suppressionWindow / 2 + 0.01
            ),
            "The swallowed toggle is consumed once; the next click opens the menu."
        )
    }

    func testToggleAfterTheSuppressionWindowPresents() {
        var toggleGuard = PopoverToggleGuard()
        toggleGuard.recordClose(uptime: 1_000)

        XCTAssertTrue(
            toggleGuard.shouldPresent(
                now: 1_000 + PopoverToggleGuard.suppressionWindow + 0.01
            )
        )
    }

    func testEachCloseRearmsSuppression() {
        var toggleGuard = PopoverToggleGuard()
        toggleGuard.recordClose(uptime: 1_000)
        XCTAssertFalse(toggleGuard.shouldPresent(now: 1_000))

        toggleGuard.recordClose(uptime: 1_010)
        XCTAssertFalse(
            toggleGuard.shouldPresent(
                now: 1_010 + PopoverToggleGuard.suppressionWindow / 2
            )
        )
    }

    func testMouseDownAndUnknownEventClosesRecord() {
        XCTAssertTrue(PopoverToggleGuard.shouldRecordClose(eventType: .leftMouseDown))
        XCTAssertTrue(PopoverToggleGuard.shouldRecordClose(eventType: .rightMouseDown))
        XCTAssertTrue(PopoverToggleGuard.shouldRecordClose(eventType: nil))
    }

    func testKeyboardAndMouseUpClosesDoNotRecord() {
        XCTAssertFalse(PopoverToggleGuard.shouldRecordClose(eventType: .keyDown))
        XCTAssertFalse(PopoverToggleGuard.shouldRecordClose(eventType: .leftMouseUp))
        XCTAssertFalse(PopoverToggleGuard.shouldRecordClose(eventType: .leftMouseDragged))
    }

    func testOnlyMouseUpTogglesSuppress() {
        XCTAssertTrue(PopoverToggleGuard.shouldSuppressToggle(eventType: .leftMouseUp))
        XCTAssertFalse(PopoverToggleGuard.shouldSuppressToggle(eventType: .keyDown))
        XCTAssertFalse(PopoverToggleGuard.shouldSuppressToggle(eventType: nil))
    }
}
