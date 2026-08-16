import XCTest
@testable import RelayBar

final class StatusItemSummaryTests: XCTestCase {
    func testStoppedActiveAndIssueFixturesProduceDistinctStates() {
        let stopped = StatusItemSummary(phases: [TunnelPhase.stopped])
        let active = StatusItemSummary(phases: [TunnelPhase.running])
        let issue = StatusItemSummary(phases: [TunnelPhase.failed("Denied")])

        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(active.state, .active)
        XCTAssertEqual(issue.state, .issue)
        XCTAssertEqual(Set([stopped.state, active.state, issue.state]).count, 3)
    }

    func testIssueWinsWhileRetainingActiveAndFailedCounts() {
        let summary = StatusItemSummary(phases: [
            TunnelPhase.running,
            .retrying(attempt: 1, maxAttempts: 3, delay: 2, message: "retry"),
            .failed("Denied"),
            .failed("Timed out"),
            .stopped
        ])

        XCTAssertEqual(summary.state, .issue)
        XCTAssertEqual(summary.activeCount, 2)
        XCTAssertEqual(summary.failedCount, 2)
        XCTAssertEqual(
            summary.accessibilityValue,
            "2 profiles failed, 2 tunnels active"
        )
    }

    func testAccessibilityValuePluralizesSingletonsAndZeroActiveIssues() {
        XCTAssertEqual(
            StatusItemSummary(phases: [TunnelPhase.starting]).accessibilityValue,
            "1 tunnel active"
        )
        XCTAssertEqual(
            StatusItemSummary(
                phases: [TunnelPhase.failed("Denied")]
            ).accessibilityValue,
            "1 profile failed, no tunnels active"
        )
        XCTAssertEqual(
            StatusItemSummary(phases: [TunnelPhase.stopped]).accessibilityValue,
            "All tunnels stopped"
        )
        XCTAssertEqual(
            StatusItemSummary(phases: [TunnelPhase.stopped]).toolTip,
            "RelayBar — All tunnels stopped"
        )
    }

    func testImageReplacementDependsOnStateRatherThanCounts() {
        let oneActive = StatusItemSummary(activeCount: 1, failedCount: 0)
        let twoActive = StatusItemSummary(activeCount: 2, failedCount: 0)
        let issue = StatusItemSummary(activeCount: 1, failedCount: 1)

        XCTAssertFalse(twoActive.requiresImageReplacement(comparedTo: oneActive))
        XCTAssertTrue(issue.requiresImageReplacement(comparedTo: twoActive))
    }
}

/// The literal key text matters more than usual here: AppKit owns these keys,
/// so a typo would not fail — it would silently leave the stranded state in
/// place and the menu-bar icon missing.
final class StatusItemDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private let autosaveName = "com.relaybarscion.RelayBarScion.status"

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "RelayBarStatusItemDefaults.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        // `setUpWithError` can throw before either is assigned, and tearDown
        // still runs, so neither may be force-unwrapped here.
        if let suiteName, let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
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

/// The rename gave the fork a new preferences domain; without this the user's
/// saved profiles stay behind in the old one and the app looks freshly
/// installed.
final class LegacyDefaultsMigrationTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() throws -> UserDefaults {
        let name = "RelayBarMigration.\(UUID().uuidString)"
        suites.append(name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    override func tearDown() {
        for name in suites {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suites = []
        super.tearDown()
    }

    func testCopiesEveryUserDataKeyIntoAnEmptyDomain() throws {
        let new = try makeDefaults()
        let old = try makeDefaults()
        for key in LegacyDefaultsMigration.migratedKeys {
            old.set(Data("\(key) payload".utf8), forKey: key)
        }

        let copied = LegacyDefaultsMigration.run(into: new, from: old)

        XCTAssertEqual(Set(copied), Set(LegacyDefaultsMigration.migratedKeys))
        for key in LegacyDefaultsMigration.migratedKeys {
            XCTAssertEqual(
                new.data(forKey: key),
                Data("\(key) payload".utf8),
                key
            )
        }
    }

    /// The old app may still be installed, so the migration reads it and
    /// leaves it intact.
    func testLeavesTheLegacyDomainUntouched() throws {
        let new = try makeDefaults()
        let old = try makeDefaults()
        old.set(Data("profiles".utf8), forKey: "savedTunnels.v2")

        LegacyDefaultsMigration.run(into: new, from: old)

        XCTAssertEqual(old.data(forKey: "savedTunnels.v2"), Data("profiles".utf8))
    }

    func testNeverOverwritesDataAlreadySavedUnderTheNewIdentity() throws {
        let new = try makeDefaults()
        let old = try makeDefaults()
        new.set(Data("mine".utf8), forKey: "savedTunnels.v2")
        old.set(Data("theirs".utf8), forKey: "savedTunnels.v2")
        old.set(Data("hosts".utf8), forKey: "remoteFiles.savedServers.v1")

        let copied = LegacyDefaultsMigration.run(into: new, from: old)

        XCTAssertEqual(new.data(forKey: "savedTunnels.v2"), Data("mine".utf8))
        XCTAssertEqual(copied, ["remoteFiles.savedServers.v1"])
    }

    func testRunsOnceEvenIfTheLegacyDomainChangesLater() throws {
        let new = try makeDefaults()
        let old = try makeDefaults()
        old.set(Data("first".utf8), forKey: "savedTunnels.v2")

        XCTAssertEqual(
            LegacyDefaultsMigration.run(into: new, from: old),
            ["savedTunnels.v2"]
        )

        new.removeObject(forKey: "savedTunnels.v2")
        old.set(Data("second".utf8), forKey: "savedTunnels.v2")

        XCTAssertEqual(LegacyDefaultsMigration.run(into: new, from: old), [])
        XCTAssertNil(new.data(forKey: "savedTunnels.v2"))
    }

    func testFreshInstallCopiesNothingAndStillMarksItselfDone() throws {
        let new = try makeDefaults()

        XCTAssertEqual(LegacyDefaultsMigration.run(into: new, from: nil), [])
        XCTAssertTrue(
            new.bool(forKey: LegacyDefaultsMigration.completionKey)
        )
    }
}
