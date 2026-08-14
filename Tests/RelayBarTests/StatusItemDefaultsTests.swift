import XCTest
@testable import RelayBar

/// The literal key text matters more than usual here: AppKit owns these keys,
/// so a typo would not fail — it would silently leave the stranded state in
/// place and the menu-bar icon missing.
final class StatusItemDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private let autosaveName = "com.lx2026.RelayBar.status"

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "RelayBarStatusItemDefaults.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferredPositionKeyMatchesAppKitFormat() {
        XCTAssertEqual(
            StatusItemDefaults.preferredPositionKey(autosaveName: "Item-0"),
            "NSStatusItem Preferred Position Item-0"
        )
    }

    func testVisibilityKeysCoverBothSystemSpellings() {
        XCTAssertEqual(
            StatusItemDefaults.visibilityKeys(autosaveName: "Item-0"),
            [
                "NSStatusItem Visible Item-0",
                "NSStatusItem VisibleCC Item-0"
            ]
        )
    }

    func testRemovingMenuBarExtraStateClearsEveryLegacyKey() {
        let legacyKeys = [
            "NSStatusItem Preferred Position Item-0",
            "NSStatusItem Visible Item-0",
            "NSStatusItem VisibleCC Item-0"
        ]
        for key in legacyKeys {
            defaults.set(0, forKey: key)
        }

        StatusItemDefaults.removeMenuBarExtraState(in: defaults)

        for key in legacyKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    func testRemovingMenuBarExtraStateLeavesTheNamedItemAlone() {
        let visibility = StatusItemDefaults.visibilityKeys(
            autosaveName: autosaveName
        )[0]
        defaults.set(true, forKey: visibility)
        defaults.set(
            410.0,
            forKey: StatusItemDefaults.preferredPositionKey(
                autosaveName: autosaveName
            )
        )

        StatusItemDefaults.removeMenuBarExtraState(in: defaults)

        XCTAssertEqual(defaults.object(forKey: visibility) as? Bool, true)
        XCTAssertEqual(
            defaults.object(
                forKey: StatusItemDefaults.preferredPositionKey(
                    autosaveName: autosaveName
                )
            ) as? Double,
            410
        )
    }

    func testPositionBeyondEveryScreenIsCleared() {
        let key = StatusItemDefaults.preferredPositionKey(
            autosaveName: autosaveName
        )
        defaults.set(4_000.0, forKey: key)

        StatusItemDefaults.repairImplausiblePreferredPosition(
            autosaveName: autosaveName,
            widestScreenWidth: 1_440,
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: key))
    }

    func testNonPositivePositionIsCleared() {
        let key = StatusItemDefaults.preferredPositionKey(
            autosaveName: autosaveName
        )
        for saved in [0.0, -12.0] {
            defaults.set(saved, forKey: key)

            StatusItemDefaults.repairImplausiblePreferredPosition(
                autosaveName: autosaveName,
                widestScreenWidth: 1_440,
                defaults: defaults
            )

            XCTAssertNil(defaults.object(forKey: key), "\(saved)")
        }
    }

    /// A saved slot the user arranged themselves has to survive launch.
    func testPlausiblePositionIsPreserved() {
        let key = StatusItemDefaults.preferredPositionKey(
            autosaveName: autosaveName
        )
        defaults.set(320.0, forKey: key)

        StatusItemDefaults.repairImplausiblePreferredPosition(
            autosaveName: autosaveName,
            widestScreenWidth: 1_440,
            defaults: defaults
        )

        XCTAssertEqual(defaults.object(forKey: key) as? Double, 320)
    }

    /// A position just past the widest screen is still reachable after a
    /// display change, so only clearly junk values are discarded.
    func testPositionWithinSlackOfTheWidestScreenIsPreserved() {
        let key = StatusItemDefaults.preferredPositionKey(
            autosaveName: autosaveName
        )
        defaults.set(1_600.0, forKey: key)

        StatusItemDefaults.repairImplausiblePreferredPosition(
            autosaveName: autosaveName,
            widestScreenWidth: 1_440,
            defaults: defaults
        )

        XCTAssertEqual(defaults.object(forKey: key) as? Double, 1_600)
    }

    func testMissingPositionIsLeftAbsent() {
        let key = StatusItemDefaults.preferredPositionKey(
            autosaveName: autosaveName
        )

        StatusItemDefaults.repairImplausiblePreferredPosition(
            autosaveName: autosaveName,
            widestScreenWidth: 1_440,
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: key))
    }
}
