import Foundation
import XCTest
@testable import RelayBar

final class PopoverSizeLimitsTests: XCTestCase {
    func testUnknownScreenAppliesOnlyTheFixedLimits() {
        let limits = PopoverSizeLimits(visibleScreenSize: nil)

        XCTAssertEqual(limits.minimum, RelayBarPopoverLayout.minimumSize)
        XCTAssertEqual(
            limits.maximum,
            CGSize(
                width: RelayBarPopoverLayout.maximumWidth,
                height: RelayBarPopoverLayout.fallbackMaximumHeight
            )
        )
    }

    func testScreenBoundsTheMaximumInsideItsMargins() {
        let limits = PopoverSizeLimits(
            visibleScreenSize: CGSize(width: 600, height: 860)
        )

        XCTAssertEqual(limits.maximum, CGSize(width: 520, height: 820))
    }

    func testWideScreenStillCapsTheWidth() {
        let limits = PopoverSizeLimits(
            visibleScreenSize: CGSize(width: 3_000, height: 1_600)
        )

        XCTAssertEqual(limits.maximum.width, RelayBarPopoverLayout.maximumWidth)
        XCTAssertEqual(limits.maximum.height, 1_560)
    }

    func testTinyScreenNeverDropsTheMaximumBelowTheMinimum() {
        let limits = PopoverSizeLimits(
            visibleScreenSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(limits.maximum, RelayBarPopoverLayout.minimumSize)
    }

    func testClampingBoundsAndRoundsBothDimensions() {
        let limits = PopoverSizeLimits(
            visibleScreenSize: CGSize(width: 1_440, height: 860)
        )

        XCTAssertEqual(
            limits.clamped(CGSize(width: 100, height: 100)),
            RelayBarPopoverLayout.minimumSize
        )
        XCTAssertEqual(
            limits.clamped(CGSize(width: 5_000, height: 5_000)),
            CGSize(width: 720, height: 820)
        )
        XCTAssertEqual(
            limits.clamped(CGSize(width: 450.4, height: 600.6)),
            CGSize(width: 450, height: 601)
        )
    }

    func testDragKeepsTheCornerUnderThePointer() {
        // Screen coordinates grow upward: dragging right and down.
        let resized = PopoverSizeLimits.resized(
            CGSize(width: 420, height: 580),
            from: CGPoint(x: 1_000, y: 300),
            to: CGPoint(x: 1_030, y: 250),
            by: .bottomTrailingCorner
        )

        XCTAssertEqual(resized, CGSize(width: 480, height: 630))
    }

    func testBottomEdgeDragChangesOnlyTheHeight() {
        let resized = PopoverSizeLimits.resized(
            CGSize(width: 420, height: 580),
            from: CGPoint(x: 1_000, y: 300),
            to: CGPoint(x: 1_030, y: 250),
            by: .bottom
        )

        XCTAssertEqual(resized, CGSize(width: 420, height: 630))
    }
}

@MainActor
final class PopoverSizeModelTests: XCTestCase {
    func testStartsAtTheDefaultSizeWhenNothingIsStored() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)

        XCTAssertEqual(model.size, RelayBarPopoverLayout.defaultSize)
    }

    func testRestoresTheStoredSize() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["width": 500.0, "height": 700.0],
            forKey: PopoverSizeModel.storageKey
        )

        let model = PopoverSizeModel(defaults: defaults)

        XCTAssertEqual(model.size, CGSize(width: 500, height: 700))
    }

    func testMalformedStoredSizeFallsBackToTheDefault() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let malformed: [Any] = [
            ["width": -10.0, "height": 700.0] as [String: Double],
            ["width": "wide", "height": 700.0] as [String: Any],
            ["height": 700.0] as [String: Double],
            "500x700"
        ]
        for stored in malformed {
            defaults.set(stored, forKey: PopoverSizeModel.storageKey)

            let model = PopoverSizeModel(defaults: defaults)

            XCTAssertEqual(
                model.size,
                RelayBarPopoverLayout.defaultSize,
                "Stored value: \(stored)"
            )
        }
    }

    func testDragResizesLiveAndPersistsOnlyWhenItEnds() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)
        model.updateVisibleScreenSize(CGSize(width: 1_440, height: 860))
        var changes: [(CGSize, Bool)] = []
        model.sizeDidChange = { changes.append(($0, $1)) }

        model.beginResize(.bottomTrailingCorner, at: CGPoint(x: 1_000, y: 300))
        model.continueResize(to: CGPoint(x: 1_020, y: 260))

        XCTAssertTrue(model.isResizing)
        XCTAssertEqual(model.size, CGSize(width: 520, height: 760))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, CGSize(width: 520, height: 760))
        XCTAssertEqual(changes.first?.1, true)
        XCTAssertNil(defaults.object(forKey: PopoverSizeModel.storageKey))

        model.endResize()

        XCTAssertFalse(model.isResizing)
        XCTAssertEqual(
            PopoverSizeModel(defaults: defaults).size,
            CGSize(width: 520, height: 760)
        )
    }

    func testBottomEdgeDragKeepsTheWidth() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)
        model.updateVisibleScreenSize(CGSize(width: 1_440, height: 860))

        model.beginResize(.bottom, at: CGPoint(x: 1_000, y: 300))
        model.continueResize(to: CGPoint(x: 1_100, y: 340))
        model.endResize()

        XCTAssertEqual(
            model.size,
            CGSize(width: RelayBarPopoverLayout.defaultSize.width, height: 680)
        )
    }

    func testDragIsClampedToTheScreen() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)
        model.updateVisibleScreenSize(CGSize(width: 1_440, height: 700))

        model.beginResize(.bottomTrailingCorner, at: CGPoint(x: 1_000, y: 300))
        model.continueResize(to: CGPoint(x: 2_000, y: -2_000))
        model.endResize()

        XCTAssertEqual(model.size, CGSize(width: 720, height: 660))
    }

    func testResizeWithoutABeganDragIsIgnored() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)

        model.continueResize(to: CGPoint(x: 5_000, y: 0))
        model.endResize()

        XCTAssertEqual(model.size, RelayBarPopoverLayout.defaultSize)
        XCTAssertNil(defaults.object(forKey: PopoverSizeModel.storageKey))
    }

    func testSmallScreenDoesNotOverwriteTheLargerPreference() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["width": 600.0, "height": 900.0],
            forKey: PopoverSizeModel.storageKey
        )
        let model = PopoverSizeModel(defaults: defaults)
        var changes: [(CGSize, Bool)] = []
        model.sizeDidChange = { changes.append(($0, $1)) }

        model.updateVisibleScreenSize(CGSize(width: 1_280, height: 700))
        XCTAssertEqual(model.size, CGSize(width: 600, height: 660))

        model.updateVisibleScreenSize(CGSize(width: 2_560, height: 1_400))
        XCTAssertEqual(model.size, CGSize(width: 600, height: 900))
        XCTAssertEqual(changes.map { $0.1 }, [false, false])
    }

    func testAccessibilityStepsResizeAndPersist() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = PopoverSizeModel(defaults: defaults)
        model.updateVisibleScreenSize(CGSize(width: 1_440, height: 860))

        model.step(.larger)

        let larger = CGSize(
            width: RelayBarPopoverLayout.defaultSize.width
                + PopoverSizeModel.accessibilityStep.width,
            height: RelayBarPopoverLayout.defaultSize.height
                + PopoverSizeModel.accessibilityStep.height
        )
        XCTAssertEqual(model.size, larger)
        XCTAssertEqual(PopoverSizeModel(defaults: defaults).size, larger)

        for _ in 0..<20 {
            model.step(.smaller)
        }

        XCTAssertEqual(model.size, RelayBarPopoverLayout.minimumSize)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RelayBarTests.PopoverSize.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
