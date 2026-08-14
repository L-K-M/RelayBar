import Foundation
import XCTest
@testable import RelayBar

final class PopoverToggleGuardTests: XCTestCase {
    func testTogglePresentsWhenNoCloseWasRecorded() {
        var toggleGuard = PopoverToggleGuard()
        XCTAssertTrue(toggleGuard.shouldPresent())
    }

    func testToggleInsideTheSuppressionWindowIsSwallowedOnce() {
        var toggleGuard = PopoverToggleGuard()
        let close = Date()
        toggleGuard.recordClose(now: close)

        XCTAssertFalse(
            toggleGuard.shouldPresent(
                now: close.addingTimeInterval(
                    PopoverToggleGuard.suppressionWindow / 2
                )
            ),
            "The action half of the click that closed the popover must not reopen it."
        )
        XCTAssertTrue(
            toggleGuard.shouldPresent(
                now: close.addingTimeInterval(
                    PopoverToggleGuard.suppressionWindow / 2 + 0.01
                )
            ),
            "The swallowed toggle is consumed once; the next click opens the menu."
        )
    }

    func testToggleAfterTheSuppressionWindowPresents() {
        var toggleGuard = PopoverToggleGuard()
        let close = Date()
        toggleGuard.recordClose(now: close)

        XCTAssertTrue(
            toggleGuard.shouldPresent(
                now: close.addingTimeInterval(
                    PopoverToggleGuard.suppressionWindow + 0.01
                )
            )
        )
    }

    func testEachCloseRearmsSuppression() {
        var toggleGuard = PopoverToggleGuard()
        let first = Date()
        toggleGuard.recordClose(now: first)
        XCTAssertFalse(toggleGuard.shouldPresent(now: first))

        let second = first.addingTimeInterval(10)
        toggleGuard.recordClose(now: second)
        XCTAssertFalse(
            toggleGuard.shouldPresent(
                now: second.addingTimeInterval(
                    PopoverToggleGuard.suppressionWindow / 2
                )
            )
        )
    }
}
