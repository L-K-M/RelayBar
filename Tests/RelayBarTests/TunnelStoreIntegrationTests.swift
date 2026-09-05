import Foundation
import XCTest
@testable import RelayBar

@MainActor
final class TunnelStoreIntegrationTests: XCTestCase {
    func testConfiguredTunnelWhenLiveTestingIsEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RELAYBAR_LIVE_TEST"] == "1",
            let sshHost = environment["RELAYBAR_LIVE_SSH_HOST"],
            !sshHost.isEmpty
        else {
            throw XCTSkip(
                "Set RELAYBAR_LIVE_TEST=1 and RELAYBAR_LIVE_SSH_HOST to run the live test."
            )
        }

        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TunnelStore.makeForTesting(defaults: defaults)
        let tunnel = Tunnel(
            name: "Live local forward",
            localPort: 3000,
            destinationHost: "127.0.0.1",
            destinationPort: 3000,
            sshHost: sshHost
        )

        store.start(tunnel)
        defer { store.stop(tunnel) }

        var reachedRunningState = false
        var lastConnectionError: Error?

        for _ in 0..<60 {
            switch store.phase(for: tunnel) {
            case .running:
                reachedRunningState = true
                var request = URLRequest(
                    url: URL(string: "http://127.0.0.1:3000/")!
                )
                request.timeoutInterval = 1
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                    XCTAssertFalse(data.isEmpty)
                    return
                } catch {
                    lastConnectionError = error
                }
            case .failed(let message):
                XCTFail(message)
                return
            case .starting, .retrying, .stopped:
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        if reachedRunningState {
            XCTFail(
                "The forward ran but was unreachable: "
                    + (lastConnectionError?.localizedDescription ?? "unknown error")
            )
        } else {
            XCTFail("The forwarding profile did not reach the running state.")
        }
    }

    func testConfiguredLocalUnixSocketWhenFlexibleLiveTestingIsEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RELAYBAR_FLEXIBLE_LIVE_TEST"] == "1",
            let sshHost = environment["RELAYBAR_LIVE_SSH_HOST"],
            !sshHost.isEmpty
        else {
            throw XCTSkip(
                "Set RELAYBAR_FLEXIBLE_LIVE_TEST=1 and RELAYBAR_LIVE_SSH_HOST to run the flexible live test."
            )
        }

        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(
                "RelayBarLiveUnix-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let socketURL = directory.appendingPathComponent("listener.sock")
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        let profile = Tunnel(
            name: "Live local Unix",
            sshHost: sshHost,
            rules: [
                ForwardingRule(
                    kind: .local,
                    listen: .unix(path: socketURL.path),
                    destination: .tcp(host: "127.0.0.1", port: 9)
                )
            ],
            streamLocalSettings: StreamLocalSettings(
                bindMask: 0o077,
                unlinkStaleSocket: true
            )
        )

        store.start(profile)
        let startupFinished = await waitUntil(timeoutIterations: 2_000) {
            switch store.phase(for: profile) {
            case .running, .failed:
                true
            case .stopped, .starting, .retrying:
                false
            }
        }
        guard startupFinished, store.phase(for: profile) == .running else {
            return XCTFail(
                "The local Unix profile did not run: \(store.phase(for: profile))"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketURL.path))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )

        store.stop(profile)

        XCTAssertEqual(store.phase(for: profile), .stopped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }

    func testMigratesLegacyCollectionTransactionallyToV2() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyTunnel(
            id: UUID(),
            name: "Legacy",
            localPort: 8080,
            destinationHost: "localhost",
            destinationPort: 3000,
            sshHost: "server",
            bindAddress: nil,
            additionalArguments: ["-p", "2222"]
        )
        defaults.set(
            try JSONEncoder().encode([legacy]),
            forKey: "savedTunnels.v1"
        )

        let store = TunnelStore.makeForTesting(defaults: defaults)

        XCTAssertEqual(store.tunnels.count, 1)
        XCTAssertEqual(store.tunnels[0].id, legacy.id)
        XCTAssertEqual(store.tunnels[0].rules[0].kind, .local)
        let v2Data = try XCTUnwrap(defaults.data(forKey: "savedTunnels.v2"))
        XCTAssertEqual(
            try JSONDecoder().decode([Tunnel].self, from: v2Data),
            store.tunnels
        )
        XCTAssertNotNil(defaults.data(forKey: "savedTunnels.v1"))
    }

    /// A corrupt profile blob used to be indistinguishable from a fresh
    /// install, and the first save() after that overwrote the only copy.
    func testUndecodableCollectionIsBackedUpBeforeStartingEmpty() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupt = Data("{ not a profile list".utf8)
        defaults.set(corrupt, forKey: "savedTunnels.v2")

        let store = TunnelStore.makeForTesting(defaults: defaults)

        XCTAssertTrue(store.tunnels.isEmpty)
        XCTAssertEqual(
            defaults.data(forKey: "savedTunnels.v2.corrupt-backup"),
            corrupt
        )

        // The backup has to survive the write that would otherwise have been
        // the moment the profiles became unrecoverable.
        store.add(
            Tunnel(
                name: "Fresh",
                localPort: 8_080,
                destinationHost: "localhost",
                destinationPort: 3_000,
                sshHost: "server"
            )
        )
        XCTAssertEqual(
            defaults.data(forKey: "savedTunnels.v2.corrupt-backup"),
            corrupt
        )
    }

    /// A corrupt v2 blob must not cost the user a usable v1 collection.
    func testUndecodableCollectionStillMigratesLegacyProfiles() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("nonsense".utf8), forKey: "savedTunnels.v2")
        let legacy = LegacyTunnel(
            id: UUID(),
            name: "Legacy",
            localPort: 8_080,
            destinationHost: "localhost",
            destinationPort: 3_000,
            sshHost: "server",
            bindAddress: nil,
            additionalArguments: []
        )
        defaults.set(
            try JSONEncoder().encode([legacy]),
            forKey: "savedTunnels.v1"
        )

        let store = TunnelStore.makeForTesting(defaults: defaults)

        XCTAssertEqual(store.tunnels.count, 1)
        XCTAssertEqual(store.tunnels[0].id, legacy.id)
        XCTAssertNotNil(defaults.data(forKey: "savedTunnels.v2.corrupt-backup"))
    }

    func testGroupMutationsNormalizeMergeAndPersistWithoutASeparateGroupStore() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        var dashboard = makeLocalProfile()
        dashboard.name = "Dashboard"
        dashboard.groupTag = "Work"
        var desktop = makeLocalProfile()
        desktop.name = "Desktop"
        desktop.groupTag = "  work  "
        var photos = makeLocalProfile()
        photos.name = "Photos"
        photos.groupTag = "Personal"
        var scratch = makeLocalProfile()
        scratch.name = "Scratch"

        store.add(dashboard)
        store.add(desktop)
        store.add(photos)
        store.add(scratch)

        XCTAssertEqual(
            store.tunnels.map(\.groupTag),
            ["Work", "Work", "Personal", nil]
        )
        XCTAssertEqual(store.groupNames, ["Personal", "Work"])

        store.move(scratch, toGroup: " work ")
        XCTAssertEqual(store.tunnels[3].groupTag, "Work")
        store.move(scratch, toGroup: nil)
        XCTAssertNil(store.tunnels[3].groupTag)

        store.renameGroup("Work", to: " personal ")

        XCTAssertEqual(store.groupNames, ["Personal"])
        XCTAssertEqual(
            store.tunnels.map(\.groupTag),
            ["Personal", "Personal", "Personal", nil]
        )

        store.ungroup("PERSONAL")

        XCTAssertTrue(store.tunnels.allSatisfy { $0.groupTag == nil })
        XCTAssertFalse(store.grouping.isGrouped)
        XCTAssertNil(defaults.object(forKey: "savedTunnelGroups"))
        let persisted = try JSONDecoder().decode(
            [Tunnel].self,
            from: try XCTUnwrap(defaults.data(forKey: "savedTunnels.v2"))
        )
        XCTAssertTrue(persisted.allSatisfy { $0.groupTag == nil })

        var invalid = makeLocalProfile()
        invalid.groupTag = String(repeating: "x", count: 33)
        store.add(invalid)
        XCTAssertEqual(store.tunnels.count, 4)
    }

    /// Task 039. Duplicating a profile appends an independent copy with fresh
    /// identities right after the original and persists it.
    func testDuplicateProfileCreatesIndependentCopyAfterTheOriginal() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        var first = makeGroupedProfile(name: "Web", port: 43_250, group: "Work")
        first.startsAtLaunch = true
        let second = makeGroupedProfile(name: "Other", port: 43_251, group: nil)
        store.add(first)
        store.add(second)

        let copy = try XCTUnwrap(store.duplicate(first))

        XCTAssertEqual(store.tunnels.count, 3)
        XCTAssertEqual(store.tunnels[1].id, copy.id)
        XCTAssertNotEqual(copy.id, first.id)
        XCTAssertEqual(copy.name, "Web copy")
        XCTAssertEqual(copy.groupTag, "Work")
        XCTAssertFalse(copy.startsAtLaunch)
        XCTAssertEqual(copy.sshHost, first.sshHost)
        XCTAssertEqual(copy.rules.count, first.rules.count)
        XCTAssertNotEqual(copy.rules[0].id, first.rules[0].id)
        XCTAssertEqual(copy.rules[0].listen, first.rules[0].listen)
        XCTAssertEqual(copy.rules[0].destination, first.rules[0].destination)
        XCTAssertTrue(copy.isSafeToRun)
        XCTAssertEqual(store.phase(for: copy), .stopped)

        let reloaded = TunnelStore.makeForTesting(defaults: defaults)
        XCTAssertEqual(reloaded.tunnels.map(\.name), ["Web", "Web copy", "Other"])
    }

    /// Task 039. An unnamed profile's copy stays unnamed so its generated
    /// display summary keeps showing; only explicit names gain the suffix.
    func testDuplicateOfUnnamedProfileStaysUnnamed() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        var profile = makeLocalProfile()
        profile.name = "  "
        store.add(profile)

        let copy = try XCTUnwrap(store.duplicate(profile))

        XCTAssertEqual(copy.name, "  ")
        XCTAssertEqual(copy.displayName, store.tunnels[0].displayName)
    }

    /// Task 039. Repeated duplicates gain Finder-style numbered names
    /// instead of colliding on one " copy" row.
    func testRepeatedDuplicatesGainNumberedNames() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        let profile = makeGroupedProfile(name: "Web", port: 43_252, group: nil)
        store.add(profile)

        let firstCopy = try XCTUnwrap(store.duplicate(profile))
        let secondCopy = try XCTUnwrap(store.duplicate(profile))
        let copyOfCopy = try XCTUnwrap(store.duplicate(firstCopy))

        XCTAssertEqual(firstCopy.name, "Web copy")
        XCTAssertEqual(secondCopy.name, "Web copy 2")
        XCTAssertEqual(copyOfCopy.name, "Web copy copy")
        // Each copy lands directly after its own source.
        XCTAssertEqual(
            store.tunnels.map(\.name),
            ["Web", "Web copy 2", "Web copy", "Web copy copy"]
        )
    }

    /// Task 009. `grouping` is cached so the list body does not rebuild sections
    /// on every phase publish. Every mutation path must invalidate it.
    func testGroupingCacheInvalidatesOnEveryMutationPath() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)

        XCTAssertFalse(store.grouping.isGrouped)

        var dashboard = makeLocalProfile()
        dashboard.name = "Dashboard"
        dashboard.groupTag = "Work"
        store.add(dashboard)
        XCTAssertEqual(store.grouping.groupNames, ["Work"])

        var renamedDashboard = store.tunnels[0]
        renamedDashboard.name = "Renamed"
        store.update(renamedDashboard)
        XCTAssertEqual(store.grouping.sections.first?.tunnels.first?.name, "Renamed")

        let duplicated = try XCTUnwrap(store.duplicate(store.tunnels[0]))
        XCTAssertEqual(
            store.grouping.sections.first?.tunnels.map(\.name),
            ["Renamed", "Renamed copy"]
        )
        store.delete(duplicated)
        XCTAssertEqual(
            store.grouping.sections.first?.tunnels.map(\.name),
            ["Renamed"]
        )

        store.move(store.tunnels[0], toGroup: "Personal")
        XCTAssertEqual(store.grouping.groupNames, ["Personal"])

        store.renameGroup("Personal", to: "Home")
        XCTAssertEqual(store.grouping.groupNames, ["Home"])

        store.ungroup("Home")
        XCTAssertFalse(store.grouping.isGrouped)

        store.delete(store.tunnels[0])
        XCTAssertTrue(store.grouping.sections.allSatisfy { $0.tunnels.isEmpty })
    }

    func testMoveAndTagOnlyUpdatePreserveStartingRunningAndPendingBrowserWork() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var openedURLs: [URL] = []
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            browserOpener: { openedURLs.append($0) }
        )
        let profile = makeLocalProfile()
        store.add(profile)

        store.openInBrowser(profile)
        XCTAssertEqual(store.phase(for: profile), .starting)
        store.move(profile, toGroup: "Work")
        XCTAssertEqual(store.phase(for: profile), .starting)

        let opened = await waitUntil { !openedURLs.isEmpty }
        XCTAssertTrue(opened)
        XCTAssertEqual(store.phase(for: profile), .running)
        let invocationCount = parsedInvocations(
            try String(contentsOf: fixture.logURL)
        ).count

        store.renameGroup("Work", to: "Client")
        XCTAssertEqual(store.phase(for: profile), .running)
        XCTAssertEqual(store.tunnels[0].groupTag, "Client")

        var edited = store.tunnels[0]
        edited.groupTag = "Operations"
        store.update(edited)
        XCTAssertEqual(store.phase(for: profile), .running)
        XCTAssertEqual(store.tunnels[0].groupTag, "Operations")

        store.ungroup("Operations")
        XCTAssertEqual(store.phase(for: profile), .running)
        XCTAssertNil(store.tunnels[0].groupTag)
        XCTAssertEqual(
            parsedInvocations(try String(contentsOf: fixture.logURL)).count,
            invocationCount
        )
        XCTAssertEqual(openedURLs, [try XCTUnwrap(profile.unambiguousBrowserURL)])
        store.stop(profile)
    }

    func testGroupMovesPreserveStoppedFailedAndRetryingPhases() async throws {
        let (stoppedDefaults, stoppedSuite) = makeIsolatedDefaults()
        defer { stoppedDefaults.removePersistentDomain(forName: stoppedSuite) }
        let stoppedStore = TunnelStore.makeForTesting(defaults: stoppedDefaults)
        let stopped = makeLocalProfile()
        stoppedStore.add(stopped)
        stoppedStore.move(stopped, toGroup: "Work")
        XCTAssertEqual(stoppedStore.phase(for: stopped), .stopped)

        let failed = Tunnel(
            name: "Invalid",
            localPort: 43_211,
            destinationHost: "localhost",
            destinationPort: 80,
            sshHost: "-blocked"
        )
        stoppedStore.add(failed)
        stoppedStore.start(failed)
        let failedPhase = stoppedStore.phase(for: failed)
        guard case .failed = failedPhase else {
            return XCTFail("Expected an invalid profile to fail.")
        }
        stoppedStore.move(failed, toGroup: "Work")
        XCTAssertEqual(stoppedStore.phase(for: failed), failedPhase)

        let (retryDefaults, retrySuite) = makeIsolatedDefaults()
        defer { retryDefaults.removePersistentDomain(forName: retrySuite) }
        let retryStore = TunnelStore(
            defaults: retryDefaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            retryDelayProvider: { _ in 1 },
            networkPathObserver: FakeNetworkPathObserver()
        )
        let retrying = makeLocalProfile()
        retryStore.add(retrying)
        retryStore.start(retrying)
        let enteredRetry = await waitUntil {
            if case .retrying = retryStore.phase(for: retrying) { return true }
            return false
        }
        XCTAssertTrue(enteredRetry)
        let retryingPhase = retryStore.phase(for: retrying)
        retryStore.move(retrying, toGroup: "Operations")
        XCTAssertEqual(retryStore.phase(for: retrying), retryingPhase)
        retryStore.stop(retrying)
    }

    /// Task 024. Start All targets only inactive members of the canonical
    /// group, marks unsafe members failed without blocking safe peers, and
    /// never relaunches an active member.
    func testStartAllStartsInactiveMembersOnceAndSkipsPeersOutsideTheGroup() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let running = makeGroupedProfile(name: "Running", port: 43_220, group: "Work")
        let stopped = makeGroupedProfile(name: "Stopped", port: 43_221, group: "Work")
        let unsafe = makeGroupedProfile(
            name: "Unsafe",
            port: 43_222,
            group: "Work",
            sshHost: "-blocked"
        )
        let otherGroup = makeGroupedProfile(name: "Other", port: 43_223, group: "Personal")
        let ungrouped = makeGroupedProfile(name: "Ungrouped", port: 43_224, group: nil)
        for profile in [running, stopped, unsafe, otherGroup, ungrouped] {
            store.add(profile)
        }
        store.start(running)
        let firstMemberRunning = await waitUntil {
            store.phase(for: running) == .running
        }
        XCTAssertTrue(firstMemberRunning)
        defer { store.stopAll() }

        store.startGroup("work")

        let stoppedMemberStarted = await waitUntil {
            store.phase(for: stopped) == .running
        }
        XCTAssertTrue(stoppedMemberStarted)
        XCTAssertEqual(store.phase(for: running), .running)
        guard case .failed = store.phase(for: unsafe) else {
            return XCTFail("Expected the unsafe member to fail visibly.")
        }
        XCTAssertEqual(store.phase(for: otherGroup), .stopped)
        XCTAssertEqual(store.phase(for: ungrouped), .stopped)
        let mastersAfterFirstBatch = masterInvocationCount(
            try String(contentsOf: fixture.logURL)
        )
        XCTAssertEqual(mastersAfterFirstBatch, 2)

        // A repeated batch start must not relaunch active members; the failed
        // unsafe member fails again before any process is spawned.
        store.startGroup("Work")
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL)),
            2
        )
    }

    /// Task 024. Stop All cancels only lifecycle-active members, so stopped
    /// peers stay stopped and a failed member keeps its visible message.
    func testStopAllStopsActiveMembersAndPreservesStoppedAndFailedPeers() async throws {
        let retryingSpec = "43231:127.0.0.1:80"
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_FAIL_SPEC": retryingSpec]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 5,
            retryDelay: 60
        )
        let running = makeGroupedProfile(name: "Running", port: 43_230, group: "Work")
        let retrying = makeGroupedProfile(name: "Retrying", port: 43_231, group: "Work")
        let failed = makeGroupedProfile(
            name: "Failed",
            port: 43_232,
            group: "Work",
            sshHost: "-blocked"
        )
        let stopped = makeGroupedProfile(name: "Stopped", port: 43_233, group: "Work")
        let outside = makeGroupedProfile(name: "Outside", port: 43_234, group: nil)
        for profile in [running, retrying, failed, stopped, outside] {
            store.add(profile)
        }
        store.start(running)
        store.start(retrying)
        store.start(outside)
        store.start(failed)
        let failedPhase = store.phase(for: failed)
        guard case .failed = failedPhase else {
            return XCTFail("Expected the invalid member to fail immediately.")
        }
        let activeMembersSettled = await waitUntil {
            var isRetrying = false
            if case .retrying = store.phase(for: retrying) { isRetrying = true }
            return isRetrying
                && store.phase(for: running) == .running
                && store.phase(for: outside) == .running
        }
        XCTAssertTrue(activeMembersSettled)
        defer { store.stopAll() }

        store.stopGroup("Work")

        XCTAssertEqual(store.phase(for: running), .stopped)
        XCTAssertEqual(store.phase(for: retrying), .stopped)
        XCTAssertEqual(store.phase(for: failed), failedPhase)
        XCTAssertEqual(store.phase(for: stopped), .stopped)
        XCTAssertEqual(store.phase(for: outside), .running)
        XCTAssertEqual(store.runningCount, 1)
    }

    /// Task 024. Restart All replaces each member active at invocation with
    /// one fresh launch and does not start members that were stopped.
    func testRestartAllRelaunchesActiveMembersAndSkipsStoppedOnes() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let active = makeGroupedProfile(name: "Active", port: 43_240, group: "Work")
        let stopped = makeGroupedProfile(name: "Stopped", port: 43_241, group: "Work")
        let outside = makeGroupedProfile(name: "Outside", port: 43_242, group: "Personal")
        for profile in [active, stopped, outside] {
            store.add(profile)
        }
        // Started one at a time: concurrent launches interleave their blocks
        // in the shared fake-ssh log and the invocation count becomes lossy.
        store.start(active)
        let firstRunning = await waitUntil {
            store.phase(for: active) == .running
        }
        XCTAssertTrue(firstRunning)
        store.start(outside)
        let secondRunning = await waitUntil {
            store.phase(for: outside) == .running
        }
        XCTAssertTrue(secondRunning)
        defer { store.stopAll() }

        store.restartGroup("Work")

        let restarted = await waitUntil {
            store.phase(for: active) == .running
        }
        XCTAssertTrue(restarted)
        XCTAssertEqual(store.phase(for: stopped), .stopped)
        XCTAssertEqual(store.phase(for: outside), .running)
        // One extra master launch for the restarted member only.
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL)),
            3
        )
    }

    /// Task 024. Batch actions resolve members by canonical group identity,
    /// so stored tags and requests that differ only by case or harmless
    /// whitespace address one group.
    func testGroupLifecycleActionsMatchCanonicalGroupIdentity() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Seeded through storage because interactive tagging normalizes new
        // tags to the existing spelling; decoded data may legitimately keep
        // members of one canonical group under differing case.
        let first = makeGroupedProfile(name: "First", port: 43_250, group: "Work")
        let second = makeGroupedProfile(name: "Second", port: 43_251, group: "wORK")
        let outside = makeGroupedProfile(name: "Outside", port: 43_252, group: "Personal")
        defaults.set(
            try JSONEncoder().encode([first, second, outside]),
            forKey: "savedTunnels.v2"
        )
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        XCTAssertEqual(store.tunnels.map(\.groupTag), ["Work", "wORK", "Personal"])
        defer { store.stopAll() }

        store.startGroup("  work ")

        let bothStarted = await waitUntil {
            store.phase(for: first) == .running
                && store.phase(for: second) == .running
        }
        XCTAssertTrue(bothStarted)
        XCTAssertEqual(store.phase(for: outside), .stopped)

        store.stopGroup("WORK")

        XCTAssertEqual(store.phase(for: first), .stopped)
        XCTAssertEqual(store.phase(for: second), .stopped)
        XCTAssertEqual(store.runningCount, 0)
    }

    /// Task 024. Membership is snapshotted when an action begins, so a member
    /// moved to another group beforehand is no longer targeted.
    func testGroupActionsResolveMembershipAtInvocation() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let moved = makeGroupedProfile(name: "Moved", port: 43_260, group: "Work")
        let remaining = makeGroupedProfile(name: "Remaining", port: 43_261, group: "Work")
        store.add(moved)
        store.add(remaining)
        store.start(moved)
        store.start(remaining)
        let bothRunning = await waitUntil {
            store.phase(for: moved) == .running
                && store.phase(for: remaining) == .running
        }
        XCTAssertTrue(bothRunning)
        defer { store.stopAll() }

        store.move(moved, toGroup: "Personal")
        store.stopGroup("Work")

        XCTAssertEqual(store.phase(for: remaining), .stopped)
        XCTAssertEqual(store.phase(for: moved), .running)

        store.stopGroup("Personal")

        XCTAssertEqual(store.phase(for: moved), .stopped)
    }

    /// Task 024. One member failing its forwarding rules must not prevent an
    /// eligible peer from reaching Running in the same batch.
    func testStartAllKeepsIndependentOutcomesWhenOneMemberFailsItsRules() async throws {
        let failingSpec = "43271:127.0.0.1:80"
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_FAIL_SPEC": failingSpec]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0
        )
        let healthy = makeGroupedProfile(name: "Healthy", port: 43_270, group: "Work")
        let failing = makeGroupedProfile(name: "Failing", port: 43_271, group: "Work")
        store.add(healthy)
        store.add(failing)
        defer { store.stopAll() }

        store.startGroup("Work")

        let outcomesSettled = await waitUntil {
            var didFail = false
            if case .failed = store.phase(for: failing) { didFail = true }
            return didFail && store.phase(for: healthy) == .running
        }
        XCTAssertTrue(outcomesSettled)
        guard case .failed(let message) = store.phase(for: failing) else {
            return XCTFail("Expected the failing member to surface its error.")
        }
        XCTAssertTrue(message.contains("fake forwarding failure"))
    }

    func testTagMutationKeepsAutomaticRuntimePortAndConnectionEditRestarts() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let rule = ForwardingRule(
            kind: .remote,
            listen: .tcp(bindAddress: "localhost", port: 0),
            destination: .tcp(host: "localhost", port: 3_000)
        )
        let profile = Tunnel(
            name: "Automatic",
            sshHost: "server",
            rules: [rule]
        )
        store.add(profile)
        store.start(profile)
        let reachedRunning = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(reachedRunning)
        let allocatedPorts = store.runtimePorts(for: profile)

        store.move(profile, toGroup: "Work")

        XCTAssertEqual(store.phase(for: profile), .running)
        XCTAssertEqual(store.runtimePorts(for: profile), allocatedPorts)

        var connectionEdit = store.tunnels[0]
        connectionEdit.sshHost = "replacement-server"
        store.update(connectionEdit)

        XCTAssertEqual(store.phase(for: profile), .starting)
        let restarted = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(restarted)
        XCTAssertFalse(store.runtimePorts(for: profile).isEmpty)
        let masterInvocations = parsedInvocations(
            try String(contentsOf: fixture.logURL)
        )
        .filter { $0.contains("-M") }
        XCTAssertEqual(masterInvocations.count, 2)
        XCTAssertEqual(masterInvocations.last?.last, "replacement-server")
        store.stop(profile)
    }

    func testEditingARunningProfileRestartsItWithTheNewDefinition() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let profile = makeLocalProfile()
        store.add(profile)
        store.start(profile)
        let reachedRunning = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(reachedRunning)

        var edited = store.tunnels[0]
        edited.sshHost = "replacement.example.com"
        store.update(edited)

        XCTAssertEqual(store.phase(for: profile), .starting)
        let restarted = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(restarted)
        XCTAssertEqual(store.tunnels[0].sshHost, "replacement.example.com")
        let masterInvocations = parsedInvocations(
            try String(contentsOf: fixture.logURL)
        )
        .filter { $0.contains("-M") }
        XCTAssertEqual(masterInvocations.count, 2)
        XCTAssertEqual(masterInvocations.last?.last, "replacement.example.com")
        store.stop(profile)
    }

    func testEditingAStoppedProfileLeavesItStopped() throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let profile = makeLocalProfile()
        store.add(profile)

        var edited = store.tunnels[0]
        edited.name = "Edited Web"
        store.update(edited)

        XCTAssertEqual(store.phase(for: profile), .stopped)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.logURL.path)
        )
    }

    func testInstallsMixedRulesSeparatelyAndMapsAutomaticPorts() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let firstAutomatic = ForwardingRule(
            kind: .remote,
            listen: .tcp(bindAddress: "localhost", port: 0),
            destination: .tcp(host: "localhost", port: 3000)
        )
        let secondAutomatic = ForwardingRule(
            kind: .remoteDynamic,
            listen: .tcp(bindAddress: "localhost", port: 0)
        )
        let profile = Tunnel(
            name: "Mixed",
            sshHost: "server",
            rules: [
                .localTCP(
                    bindAddress: "localhost",
                    port: 8080,
                    destinationHost: "web",
                    destinationPort: 80
                ),
                ForwardingRule(
                    kind: .localDynamic,
                    listen: .tcp(bindAddress: "localhost", port: 1080)
                ),
                firstAutomatic,
                secondAutomatic
            ],
            reverseSOCKSPolicy: .allow(["example.com:443"])
        )

        store.start(profile)
        defer { store.stop(profile) }
        let reachedRunning = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(reachedRunning)

        XCTAssertEqual(
            store.runtimePorts(for: profile),
            [firstAutomatic.id: 47_000, secondAutomatic.id: 47_001]
        )

        let log = try String(contentsOf: fixture.logURL)
        let invocations = parsedInvocations(log)
        XCTAssertEqual(invocations.count, 5)
        XCTAssertTrue(invocations[0].contains("-M"))
        XCTAssertTrue(invocations[0].contains("ClearAllForwardings=yes"))
        XCTAssertTrue(
            invocations[0].contains(
                "PermitRemoteOpen=example.com:443"
            )
        )
        XCTAssertFalse(invocations[0].contains("-L"))
        XCTAssertTrue(invocations.contains { invocation in
            invocation.contains("-L")
                && invocation.contains("localhost:8080:web:80")
        })
        XCTAssertTrue(invocations.contains { invocation in
            invocation.contains("-D") && invocation.contains("localhost:1080")
        })
        XCTAssertTrue(invocations.contains { invocation in
            invocation.contains("-R")
                && invocation.contains("localhost:0:localhost:3000")
        })
        XCTAssertTrue(invocations.contains { invocation in
            invocation.contains("-R") && invocation.contains("localhost:0")
        })
        for helper in invocations.dropFirst() {
            XCTAssertTrue(helper.starts(with: ["-F", "none"]))
        }
    }

    func testRuleFailureRollsBackProfileAndStopsAfterConfiguredRetries() async throws {
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_FAIL_SPEC": "localhost:1080"]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0
        )
        let profile = Tunnel(
            name: "Failure",
            sshHost: "server",
            rules: [
                .localTCP(
                    bindAddress: "localhost",
                    port: 8080,
                    destinationHost: "web",
                    destinationPort: 80
                ),
                ForwardingRule(
                    kind: .localDynamic,
                    listen: .tcp(bindAddress: "localhost", port: 1080)
                )
            ]
        )

        store.start(profile)

        let reachedFailure = await waitUntil {
            if case .failed = store.phase(for: profile) { return true }
            return false
        }
        XCTAssertTrue(reachedFailure)
        guard case .failed(let message) = store.phase(for: profile) else {
            return XCTFail("Expected a failed profile.")
        }
        XCTAssertTrue(message.contains("fake forwarding failure"))
        XCTAssertTrue(store.runtimePorts(for: profile).isEmpty)
        XCTAssertEqual(store.runningCount, 0)
    }

    func testHungControlOperationTimesOutAndRollsBackProfile() async throws {
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_DELAY_SPEC": "localhost:1080"]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            controlOperationTimeout: 0.1
        )
        let profile = Tunnel(
            name: "Hung helper",
            sshHost: "server",
            rules: [
                ForwardingRule(
                    kind: .localDynamic,
                    listen: .tcp(bindAddress: "localhost", port: 1080)
                )
            ]
        )

        store.start(profile)

        let reachedFailure = await waitUntil {
            if case .failed = store.phase(for: profile) { return true }
            return false
        }
        XCTAssertTrue(reachedFailure)
        guard case .failed(let message) = store.phase(for: profile) else {
            return XCTFail("Expected a failed profile.")
        }
        XCTAssertTrue(message.contains("timed out"))
        XCTAssertEqual(store.runningCount, 0)
    }

    func testAutomaticPortsClearOnStopAndChangeAfterRestart() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let rule = ForwardingRule(
            kind: .remote,
            listen: .tcp(bindAddress: "localhost", port: 0),
            destination: .tcp(host: "localhost", port: 3000)
        )
        let profile = Tunnel(name: "Automatic", sshHost: "server", rules: [rule])

        store.start(profile)
        let firstStartRunning = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(firstStartRunning)
        XCTAssertEqual(store.runtimePorts(for: profile)[rule.id], 47_000)

        store.stop(profile)
        XCTAssertTrue(store.runtimePorts(for: profile).isEmpty)
        XCTAssertEqual(store.phase(for: profile), .stopped)

        store.start(profile)
        defer { store.stop(profile) }
        let secondStartRunning = await waitUntil {
            store.phase(for: profile) == .running
        }
        XCTAssertTrue(secondStartRunning)
        XCTAssertEqual(store.runtimePorts(for: profile)[rule.id], 47_001)
    }

    /// Task 007. The stopped launch's control operation outlives `stop`, because
    /// the fixture ignores SIGTERM. Control state is scoped to the launch that
    /// owns it, so the replacement launch must not see a conflict.
    func testRestartIsNotBlockedByAStoppedLaunchesControlOperation() async throws {
        let rule = ForwardingRule(
            kind: .local,
            listen: .tcp(bindAddress: "localhost", port: 4_501),
            destination: .tcp(host: "localhost", port: 3_000)
        )
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_IGNORE_TERM_SPEC": rule.specification]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let profile = Tunnel(name: "Restart", sshHost: "server", rules: [rule])

        store.start(profile)
        let controlOperationStarted = await waitUntil {
            let log = (try? String(contentsOf: fixture.logURL, encoding: .utf8)) ?? ""
            return log.contains("ARG:forward")
        }
        XCTAssertTrue(controlOperationStarted)

        // Still in flight: stop and restart before it can be reaped.
        store.stop(profile)
        XCTAssertEqual(store.phase(for: profile), .stopped)
        XCTAssertEqual(store.terminatingSSHProcessCount, 2)
        store.start(profile)
        defer { store.stop(profile) }

        let restarted = await waitUntil(timeoutIterations: 800) {
            store.phase(for: profile) == .running
        }
        if case .failed(let message) = store.phase(for: profile) {
            XCTFail("Restart failed: \(message)")
        }
        XCTAssertTrue(restarted)
    }

    func testRefusesToReplaceExistingLocalSocketPath() throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let socketPath = "/tmp/RelayBarTest-\(UUID().uuidString.prefix(8)).sock"
        defer { try? FileManager.default.removeItem(atPath: socketPath) }
        try Data("not a socket".utf8).write(
            to: URL(fileURLWithPath: socketPath)
        )
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let profile = Tunnel(
            name: "Socket",
            sshHost: "server",
            rules: [
                ForwardingRule(
                    kind: .local,
                    listen: .unix(path: socketPath),
                    destination: .tcp(host: "localhost", port: 3000)
                )
            ],
            streamLocalSettings: StreamLocalSettings(
                bindMask: 0o077,
                unlinkStaleSocket: true
            )
        )

        store.start(profile)

        guard case .failed(let message) = store.phase(for: profile) else {
            return XCTFail("Expected preflight failure.")
        }
        XCTAssertTrue(message.contains("will not replace"))
        XCTAssertEqual(
            try String(contentsOfFile: socketPath),
            "not a socket"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.logURL.path))
    }

    /// Task 049. Exhausting automatic retries posts one notification so a
    /// tunnel that gives up while the popover is closed is never silent.
    func testRetryExhaustionPostsAFailureNotification() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var notifications: [(name: String, message: String)] = []
        let store = TunnelStore(
            defaults: defaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            maxRetryAttempts: 2,
            retryDelayProvider: { _ in 0.01 },
            failureNotifier: { name, message in
                notifications.append((name, message))
            },
            networkPathObserver: FakeNetworkPathObserver()
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)

        store.start(tunnel)
        let retriesExhausted = await waitUntil {
            if case .failed = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(retriesExhausted)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].name, "Web")
        XCTAssertTrue(notifications[0].message.contains("Automatic retry stopped after 2 attempts."))
    }

    func testUnexpectedExitRetriesUntilLimit() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TunnelStore(
            defaults: defaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            maxRetryAttempts: 2,
            retryDelayProvider: { _ in 0.01 },
            networkPathObserver: FakeNetworkPathObserver()
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)

        store.start(tunnel)

        let retriesExhausted = await waitUntil {
            if case .failed = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(retriesExhausted)
        guard case .failed(let message) = store.phase(for: tunnel) else {
            return XCTFail("Expected retries to exhaust.")
        }
        XCTAssertTrue(message.contains("Automatic retry stopped after 2 attempts."))
        XCTAssertEqual(store.runningCount, 0)
    }

    func testForwardingControlPathRejectsOverlongRootWithoutResidue() throws {
        let root = URL(
            fileURLWithPath:
                "/tmp/RelayBarOverlong-"
                + String(repeating: "x", count: 64)
                + "-"
                + String(UUID().uuidString.prefix(8)),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore(
            defaults: defaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            maxRetryAttempts: 0,
            temporaryDirectory: root,
            networkPathObserver: FakeNetworkPathObserver()
        )
        let tunnel = makeLocalProfile()

        store.start(tunnel)

        guard case .failed(let message) = store.phase(for: tunnel) else {
            return XCTFail("Expected an overlong forwarding control path to fail.")
        }
        XCTAssertTrue(message.contains("too long"))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
            "A rejected forwarding control path must not leave a private directory."
        )
    }

    func testManualStopCancelsPendingRetry() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TunnelStore(
            defaults: defaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            retryDelayProvider: { _ in 0.2 },
            networkPathObserver: FakeNetworkPathObserver()
        )
        let tunnel = makeLocalProfile()
        store.start(tunnel)

        let enteredRetry = await waitUntil {
            if case .retrying = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(enteredRetry)

        store.stop(tunnel)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(store.phase(for: tunnel), .stopped)
        XCTAssertEqual(store.runningCount, 0)
    }

    /// Task 040. The store records when a pending retry fires so the row can
    /// count down live; stopping the profile clears the deadline.
    func testRetryDeadlineTracksScheduledRetryAndClearsOnStop() async throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore(
            defaults: defaults,
            sshExecutableURL: URL(fileURLWithPath: "/usr/bin/false"),
            retryDelayProvider: { _ in 5 },
            networkPathObserver: FakeNetworkPathObserver()
        )
        let tunnel = makeLocalProfile()
        store.start(tunnel)

        let enteredRetry = await waitUntil {
            if case .retrying = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(enteredRetry)
        let deadline = try XCTUnwrap(store.retryDeadline(for: tunnel))
        XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 3)
        XCTAssertLessThan(deadline.timeIntervalSinceNow, 6)

        store.stop(tunnel)
        XCTAssertNil(store.retryDeadline(for: tunnel))
    }

    func testStopTracksMasterUntilItsTerminationCallbackArrives() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let tunnel = makeLocalProfile()

        store.start(tunnel)
        let reachedRunning = await waitUntil {
            store.phase(for: tunnel) == .running
        }
        XCTAssertTrue(reachedRunning)

        store.stop(tunnel)
        XCTAssertEqual(store.phase(for: tunnel), .stopped)
        XCTAssertEqual(store.terminatingSSHProcessCount, 1)
        let processExited = await waitUntil {
            store.terminatingSSHProcessCount == 0
        }
        XCTAssertTrue(processExited)
    }

    func testStopForceKillsMasterThatIgnoresSIGTERM() async throws {
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_IGNORE_MASTER_TERM": "1"]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            processTerminationGracePeriod: 0.1
        )
        let tunnel = makeLocalProfile()

        store.start(tunnel)
        let reachedRunning = await waitUntil {
            store.phase(for: tunnel) == .running
        }
        XCTAssertTrue(reachedRunning)

        store.stop(tunnel)
        XCTAssertEqual(store.terminatingSSHProcessCount, 1)
        let processExited = await waitUntil {
            store.terminatingSSHProcessCount == 0
        }
        XCTAssertTrue(processExited)
    }

    /// Task 063. A network path change ends a pending backoff at once and the
    /// attempt count starts over, because the failures behind it happened on a
    /// network that no longer exists.
    func testNetworkChangeRelaunchesRetryingProfileWithAFreshAttemptCount() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 10,
            retryDelayProvider: { attempt in attempt == 1 ? 0.01 : 60 },
            networkPathObserver: network
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)
        store.start(tunnel)
        defer { store.stop(tunnel) }

        let waitingOutTheLongBackoff = await waitUntil {
            if case .retrying(let attempt, _, _, _) = store.phase(for: tunnel) {
                return attempt == 2
            }
            return false
        }
        XCTAssertTrue(
            waitingOutTheLongBackoff,
            "Expected the attempt-2 backoff after two failed launches: \(store.phase(for: tunnel))"
        )
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8)),
            2
        )

        network.simulateChange()

        // With the count reset, the relaunch fails into attempt 1, whose short
        // delay produces one more launch before attempt 2's long wait: four
        // masters in the log and a profile retrying as attempt 2. Without the
        // reset there would be a single relaunch straight into attempt 3.
        let settledIntoASecondLadder = await waitUntil {
            guard
                case .retrying(let attempt, _, _, _) = store.phase(for: tunnel),
                attempt == 2
            else {
                return false
            }
            let log = (try? String(contentsOf: fixture.logURL, encoding: .utf8)) ?? ""
            return self.masterInvocationCount(log) == 4
        }
        XCTAssertTrue(
            settledIntoASecondLadder,
            "Unexpected phase after the network change: \(store.phase(for: tunnel))"
        )
    }

    /// Task 063. The VPN scenario end to end: an outage outlasts the retry
    /// budget, the profile fails with a message that promises another try,
    /// and the next network path change brings it back to Running on its own.
    func testNetworkChangeRestartsProfileWhoseRetriesRanOutDuringAnOutage() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let notifications = NotificationLog()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 1,
            failureNotifier: { name, message in
                notifications.entries.append((name, message))
            },
            networkPathObserver: network,
            networkChangeSettleDelay: 0.01
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)
        store.start(tunnel)
        defer { store.stopAll() }

        let retriesRanOut = await waitUntil {
            if case .failed = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(retriesRanOut)
        guard case .failed(let message) = store.phase(for: tunnel) else {
            return XCTFail("Expected the outage to exhaust retries.")
        }
        XCTAssertTrue(message.contains("Automatic retry stopped after 1 attempt."))
        XCTAssertTrue(message.contains("RelayBar tries again when the network changes."))
        XCTAssertEqual(notifications.entries.count, 1)
        XCTAssertEqual(store.runningCount, 0)
        let launchesDuringOutage = masterInvocationCount(
            try String(contentsOf: fixture.logURL, encoding: .utf8)
        )
        XCTAssertEqual(launchesDuringOutage, 2)

        // The VPN drops: the host is reachable again and the path changes.
        try FileManager.default.removeItem(at: outage)
        network.simulateChange()

        let reconnected = await waitUntil {
            store.phase(for: tunnel) == .running
        }
        XCTAssertTrue(reconnected)
        XCTAssertEqual(store.runningCount, 1)
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8)),
            launchesDuringOutage + 1
        )
        XCTAssertEqual(notifications.entries.count, 1)
    }

    /// Task 063. Only the user's standing intent survives exhaustion: stopping
    /// the failed profile withdraws it, so the next network change leaves it
    /// stopped.
    func testStopAfterExhaustionWithdrawsTheNetworkChangeRetry() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            networkPathObserver: network,
            networkChangeSettleDelay: 0.01
        )
        let tunnel = makeLocalProfile()
        // Exhausted alongside the profile under test but never stopped, so
        // its return proves the reconnect pass ran.
        let witness = makeGroupedProfile(name: "Witness", port: 43_284, group: nil)
        store.add(tunnel)
        store.add(witness)
        store.start(tunnel)
        store.start(witness)
        defer { store.stopAll() }

        let retriesRanOut = await waitUntil {
            var count = 0
            if case .failed = store.phase(for: tunnel) { count += 1 }
            if case .failed = store.phase(for: witness) { count += 1 }
            return count == 2
        }
        XCTAssertTrue(retriesRanOut)

        store.stop(tunnel)
        XCTAssertEqual(store.phase(for: tunnel), .stopped)

        try FileManager.default.removeItem(at: outage)
        network.simulateChange()

        let witnessReturned = await waitUntil { store.phase(for: witness) == .running }
        XCTAssertTrue(witnessReturned, "Phase: \(store.phase(for: witness))")
        XCTAssertEqual(store.phase(for: tunnel), .stopped)
        XCTAssertEqual(store.runningCount, 1)
    }

    /// Task 063. Stopping a group also withdraws an exhausted member from the
    /// network-change retry — a group the user stopped stays stopped when the
    /// VPN drops — while a member that failed for a configuration reason
    /// keeps its phase and message as before.
    func testStopGroupWithdrawsExhaustedMembersFromTheNetworkChangeRetry() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            networkPathObserver: network,
            networkChangeSettleDelay: 0.01
        )
        let exhausted = makeGroupedProfile(name: "Exhausted", port: 43_280, group: "Work")
        let running = makeGroupedProfile(name: "Running", port: 43_281, group: "Work")
        let misconfigured = makeGroupedProfile(
            name: "Misconfigured",
            port: 43_282,
            group: "Work",
            sshHost: "-blocked"
        )
        // Outside the group, so Stop All never touches it: the witness that
        // the reconnect pass really ran.
        let armed = makeGroupedProfile(name: "Armed", port: 43_283, group: nil)
        for profile in [exhausted, running, misconfigured, armed] {
            store.add(profile)
        }
        defer { store.stopAll() }

        store.start(exhausted)
        store.start(armed)
        let retriesRanOut = await waitUntil {
            var count = 0
            if case .failed = store.phase(for: exhausted) { count += 1 }
            if case .failed = store.phase(for: armed) { count += 1 }
            return count == 2
        }
        XCTAssertTrue(retriesRanOut)

        try FileManager.default.removeItem(at: outage)
        store.start(running)
        let peerRunning = await waitUntil {
            store.phase(for: running) == .running
        }
        XCTAssertTrue(peerRunning)
        store.start(misconfigured)
        // `start` rejects an unsafe profile before any asynchronous work, so
        // the phase is final on return; the group tests above rely on this.
        let misconfiguredPhase = store.phase(for: misconfigured)
        guard case .failed = misconfiguredPhase else {
            return XCTFail("Expected the misconfigured member to fail immediately.")
        }

        store.stopGroup("Work")

        XCTAssertEqual(store.phase(for: exhausted), .stopped)
        XCTAssertEqual(store.phase(for: running), .stopped)
        XCTAssertEqual(store.phase(for: misconfigured), misconfiguredPhase)

        network.simulateChange()

        // The witness comes back, which is what makes the rest a real check
        // rather than a race against the pass.
        let witnessReturned = await waitUntil { store.phase(for: armed) == .running }
        XCTAssertTrue(witnessReturned, "Phase: \(store.phase(for: armed))")
        XCTAssertEqual(store.phase(for: exhausted), .stopped)
        XCTAssertEqual(store.phase(for: running), .stopped)
        XCTAssertEqual(store.phase(for: misconfigured), misconfiguredPhase)
        // Its phase alone cannot tell "never tried" from "tried and rejected
        // again": its host is unique, so the log settles that.
        XCTAssertFalse(
            try String(contentsOf: fixture.logURL, encoding: .utf8).contains("-blocked"),
            "A pass must not launch a profile that start rejects."
        )
    }

    /// Task 063. A reconnect pass leaves a Running master alone: a connection
    /// the change did not sever — a split-tunnel VPN, say — keeps its process
    /// and its sessions.
    ///
    /// A second profile waiting out a long backoff is the witness. The pass
    /// must relaunch exactly it, so the launch count proves the pass ran
    /// rather than merely that the assertions arrived before it did.
    func testNetworkChangeLeavesARunningProfileAlone() async throws {
        let witnessPort = 43_296
        let witnessSpec = "\(witnessPort):127.0.0.1:80"
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_FAIL_SPEC": witnessSpec]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 5,
            retryDelay: 60,
            networkPathObserver: network
        )
        let tunnel = makeLocalProfile()
        let witness = makeGroupedProfile(name: "Witness", port: witnessPort, group: nil)
        store.add(tunnel)
        store.add(witness)
        defer { store.stopAll() }

        store.start(tunnel)
        let running = await waitUntil { store.phase(for: tunnel) == .running }
        XCTAssertTrue(running, "Phase: \(store.phase(for: tunnel))")
        store.start(witness)
        let waiting = await waitUntil {
            if case .retrying = store.phase(for: witness) { return true }
            return false
        }
        XCTAssertTrue(waiting, "Phase: \(store.phase(for: witness))")
        let runningSpec = try XCTUnwrap(
            store.tunnels.first { $0.id == tunnel.id }?.rules.first?.specification
        )
        let logBefore = try String(contentsOf: fixture.logURL, encoding: .utf8)
        let launches = masterInvocationCount(logBefore)
        let runningInstalls = forwardInstallCount(logBefore, spec: runningSpec)
        let witnessInstalls = forwardInstallCount(logBefore, spec: witnessSpec)

        network.simulateChange()

        // The witness installs its rule again; the running profile does not
        // install its own a second time, which it would have to after a
        // relaunch. One extra master total, and it is the witness's.
        let passRan = await waitUntil {
            let log = (try? String(contentsOf: fixture.logURL, encoding: .utf8)) ?? ""
            return self.forwardInstallCount(log, spec: witnessSpec) == witnessInstalls + 1
        }
        XCTAssertTrue(passRan)
        XCTAssertEqual(store.phase(for: tunnel), .running)

        try await Task.sleep(for: .milliseconds(200))
        let logAfter = try String(contentsOf: fixture.logURL, encoding: .utf8)
        XCTAssertEqual(forwardInstallCount(logAfter, spec: runningSpec), runningInstalls)
        XCTAssertEqual(masterInvocationCount(logAfter), launches + 1)
        XCTAssertEqual(store.phase(for: tunnel), .running)
    }

    /// Task 063. A VPN reconfigures its interface, routes, and DNS in a burst
    /// of path updates. Each update restarts the settle window, so one
    /// reconnect pass runs once the network has been quiet for the whole
    /// window — not partway through the burst, and not once per update.
    func testBurstOfNetworkChangesCoalescesIntoOnePassAfterTheLastOne() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            networkPathObserver: network,
            networkChangeSettleDelay: 6
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)
        store.start(tunnel)
        defer { store.stopAll() }

        let retriesRanOut = await waitUntil {
            if case .failed = store.phase(for: tunnel) { return true }
            return false
        }
        XCTAssertTrue(retriesRanOut)
        let launchesDuringOutage = masterInvocationCount(
            try String(contentsOf: fixture.logURL, encoding: .utf8)
        )
        try FileManager.default.removeItem(at: outage)

        network.simulateChange()
        try await Task.sleep(for: .seconds(4))
        network.simulateChange()
        // With a 6 s window: the second update lands 2 s before a window
        // measured from the first could fire, and this check lands 1 s after
        // that window would have fired and 3 s before the second one does.
        // Sleeps only ever overshoot; the first has 2 s of room, the second
        // 3 s.
        try await Task.sleep(for: .seconds(3))

        guard case .failed = store.phase(for: tunnel) else {
            return XCTFail(
                "The pass ran before the network was quiet for the whole window: "
                    + "\(store.phase(for: tunnel))"
            )
        }

        // The pass is still 3 s away at this point, so this wait needs more
        // than the default four-second budget to see it through.
        let reconnected = await waitUntil(timeoutIterations: 1_200) {
            store.phase(for: tunnel) == .running
        }
        XCTAssertTrue(reconnected, "Phase: \(store.phase(for: tunnel))")
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8)),
            launchesDuringOutage + 1
        )
    }

    /// Task 063. Stop All and delete withdraw exhausted profiles as well, so
    /// the next network change starts neither the stopped profile nor the
    /// deleted one.
    func testStopAllAndDeleteWithdrawExhaustedProfilesFromTheNetworkChangeRetry() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            networkPathObserver: network
        )
        defer { store.stopAll() }
        let deleted = makeGroupedProfile(name: "Deleted", port: 43_290, group: nil)
        let stopped = makeGroupedProfile(name: "Stopped", port: 43_291, group: nil)
        let witness = makeGroupedProfile(name: "Witness", port: 43_292, group: nil)
        store.add(deleted)
        store.add(stopped)
        store.add(witness)
        store.start(deleted)
        store.start(stopped)
        let bothRanOut = await waitUntil {
            var count = 0
            if case .failed = store.phase(for: deleted) { count += 1 }
            if case .failed = store.phase(for: stopped) { count += 1 }
            return count == 2
        }
        XCTAssertTrue(bothRanOut)
        let launchesDuringOutage = masterInvocationCount(
            try String(contentsOf: fixture.logURL, encoding: .utf8)
        )

        store.delete(deleted)
        store.stopAll()
        XCTAssertEqual(store.tunnels.map(\.id), [stopped.id, witness.id])
        // Stop All reached a profile owning no process, retry or startup
        // task: without that, its phase would still be failed.
        XCTAssertEqual(store.phase(for: stopped), .stopped)

        // Armed after Stop All, so it survives it and its return is what
        // proves the reconnect pass ran at all.
        store.start(witness)
        let witnessRanOut = await waitUntil {
            if case .failed = store.phase(for: witness) { return true }
            return false
        }
        XCTAssertTrue(witnessRanOut, "Phase: \(store.phase(for: witness))")
        let launchesBeforeChange = masterInvocationCount(
            try String(contentsOf: fixture.logURL, encoding: .utf8)
        )
        XCTAssertEqual(launchesBeforeChange, launchesDuringOutage + 1)

        try FileManager.default.removeItem(at: outage)
        network.simulateChange()

        let witnessReturned = await waitUntil { store.phase(for: witness) == .running }
        XCTAssertTrue(witnessReturned, "Phase: \(store.phase(for: witness))")
        XCTAssertEqual(store.phase(for: stopped), .stopped)
        XCTAssertEqual(store.runningCount, 1)
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8)),
            launchesBeforeChange + 1
        )
    }

    /// Task 063. A network change grants a fresh attempt count only a few
    /// times within one ladder, so a profile that fails for a reason no
    /// network can cure still runs out of attempts and notifies on a network
    /// that never stops changing. The immediate relaunch is not rationed, and
    /// neither is the start after exhaustion: each later change tries once
    /// more, with a new budget for the ladder it begins.
    func testNetworkChangesResetTheLadderOnlyAFewTimesPerLadder() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let notifications = NotificationLog()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 1,
            retryDelay: 60,
            failureNotifier: { name, message in
                notifications.entries.append((name, message))
            },
            networkPathObserver: network
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)
        store.start(tunnel)
        defer { store.stopAll() }

        func launches() throws -> Int {
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8))
        }
        func waitForBackoff(after expectedLaunches: Int) async -> Bool {
            await waitUntil {
                guard case .retrying = store.phase(for: tunnel) else { return false }
                return (try? launches()) == expectedLaunches
            }
        }

        let firstBackoff = await waitForBackoff(after: 1)
        XCTAssertTrue(firstBackoff, "Initial phase: \(store.phase(for: tunnel))")

        // The per-ladder reset budget from process-lifecycle.md. Each of
        // these changes relaunches at once with a fresh count, so attempt 1
        // fails into another attempt-1 backoff instead of exhausting.
        let ladderResetBudget = TunnelStore.maxNetworkChangeLadderResets
        for change in 1...ladderResetBudget {
            network.simulateChange()
            let relaunched = await waitForBackoff(after: change + 1)
            XCTAssertTrue(relaunched, "Change \(change): \(store.phase(for: tunnel))")
            XCTAssertTrue(notifications.entries.isEmpty)
        }

        // The fourth relaunch keeps its count, so its failure is attempt 2 of
        // a one-attempt ladder: exhaustion, one notification, still wanted.
        network.simulateChange()
        let ranOut = await waitUntil { notifications.entries.count == 1 }
        XCTAssertTrue(ranOut, "Phase after the fourth change: \(store.phase(for: tunnel))")
        XCTAssertEqual(try launches(), 5)
        XCTAssertTrue(
            notifications.entries.first?.message
                .hasSuffix("RelayBar tries again when the network changes.") == true
        )

        // A change after exhaustion starts the profile again, and the new
        // launch gets its own ladder resets.
        network.simulateChange()
        let restarted = await waitForBackoff(after: 6)
        XCTAssertTrue(restarted, "After the fifth change: \(store.phase(for: tunnel))")
        network.simulateChange()
        let resetAgain = await waitForBackoff(after: 7)
        XCTAssertTrue(resetAgain, "After the sixth change: \(store.phase(for: tunnel))")
        XCTAssertEqual(notifications.entries.count, 1)
    }

    /// Task 063. Restart All acts on members that own lifecycle work, which
    /// an exhausted profile does not, so it stays failed and stays armed for
    /// the next network change instead of being launched or withdrawn.
    func testRestartAllLeavesAnExhaustedMemberArmedForTheNextNetworkChange() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            networkPathObserver: network
        )
        let exhausted = makeGroupedProfile(name: "Exhausted", port: 43_300, group: "Work")
        store.add(exhausted)
        store.start(exhausted)
        defer { store.stopAll() }

        let retriesRanOut = await waitUntil {
            if case .failed = store.phase(for: exhausted) { return true }
            return false
        }
        XCTAssertTrue(retriesRanOut)
        let failedPhase = store.phase(for: exhausted)
        let launchesDuringOutage = masterInvocationCount(
            try String(contentsOf: fixture.logURL, encoding: .utf8)
        )

        store.restartGroup("Work")
        // Sampled across the window: a relaunch that failed back quickly
        // would be invisible to one reading at the end.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertEqual(store.phase(for: exhausted), failedPhase)
        }

        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8)),
            launchesDuringOutage
        )

        // Still armed: the next change brings it back.
        try FileManager.default.removeItem(at: outage)
        network.simulateChange()
        let reconnected = await waitUntil { store.phase(for: exhausted) == .running }
        XCTAssertTrue(reconnected, "Phase after the change: \(store.phase(for: exhausted))")
    }

    /// Task 063. A profile no network change can fix keeps being started by
    /// later changes — that is the point — but says so once. Only reaching
    /// Running, or the user starting it again, earns another notification.
    func testExhaustionNotifiesOncePerDeadStreak() async throws {
        let outage = try makeOutageMarker()
        let fixture = try makeFakeSSHFixture(
            overrides: ["RELAYBAR_FAKE_SSH_OUTAGE_FILE": outage.path]
        )
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let network = FakeNetworkPathObserver()
        let notifications = NotificationLog()
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            maxRetryAttempts: 0,
            failureNotifier: { name, message in
                notifications.entries.append((name, message))
            },
            networkPathObserver: network
        )
        let tunnel = makeLocalProfile()
        store.add(tunnel)
        defer { store.stopAll() }

        func launches() throws -> Int {
            masterInvocationCount(try String(contentsOf: fixture.logURL, encoding: .utf8))
        }
        func waitForExhaustion(after expectedLaunches: Int) async -> Bool {
            await waitUntil {
                guard case .failed = store.phase(for: tunnel) else { return false }
                return (try? launches()) == expectedLaunches
            }
        }

        store.start(tunnel)
        let firstExhaustion = await waitForExhaustion(after: 1)
        XCTAssertTrue(firstExhaustion, "Phase: \(store.phase(for: tunnel))")
        XCTAssertEqual(notifications.entries.count, 1)

        // Started again by the change, fails again, stays quiet.
        network.simulateChange()
        let secondExhaustion = await waitForExhaustion(after: 2)
        XCTAssertTrue(secondExhaustion, "Phase: \(store.phase(for: tunnel))")
        XCTAssertEqual(notifications.entries.count, 1)

        network.simulateChange()
        let thirdExhaustion = await waitForExhaustion(after: 3)
        XCTAssertTrue(thirdExhaustion, "Phase: \(store.phase(for: tunnel))")
        XCTAssertEqual(notifications.entries.count, 1)

        // The user asking again earns another notification.
        store.stop(tunnel)
        store.start(tunnel)
        let fourthExhaustion = await waitForExhaustion(after: 4)
        XCTAssertTrue(fourthExhaustion, "Phase: \(store.phase(for: tunnel))")
        XCTAssertEqual(notifications.entries.count, 2)
    }

    /// Task 063. The system monitor's first report describes the network the
    /// app started on and must not count as a change.
    func testNetworkPathMonitorTreatsTheFirstReportAsBaseline() {
        // `monitor: nil` means manual mode: a live NWPathMonitor would deliver
        // its own first report and consume the baseline before the calls below.
        let monitor = NetworkPathMonitor(monitor: nil)
        let changes = ChangeCounter()
        monitor.startObserving { changes.count += 1 }

        monitor.pathDidUpdate()
        XCTAssertEqual(changes.count, 0)

        monitor.pathDidUpdate()
        monitor.pathDidUpdate()
        XCTAssertEqual(changes.count, 2)
    }

    func testRetryDelayUsesExponentialBackoffWithCap() {
        XCTAssertEqual(TunnelStore.retryDelay(for: 1), 1)
        XCTAssertEqual(TunnelStore.retryDelay(for: 2), 2)
        XCTAssertEqual(TunnelStore.retryDelay(for: 3), 4)
        XCTAssertEqual(TunnelStore.retryDelay(for: 6), 32)
        XCTAssertEqual(TunnelStore.retryDelay(for: 7), 60)
        XCTAssertEqual(TunnelStore.retryDelay(for: 10), 60)
    }

    func testBrowserOpenWaitsUntilAllRulesAreInstalled() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var openedURLs: [URL] = []
        let store = makeFakeStore(
            defaults: defaults,
            fixture: fixture,
            browserOpener: { openedURLs.append($0) }
        )
        let tunnel = makeLocalProfile()

        store.openInBrowser(tunnel)

        let opened = await waitUntil { !openedURLs.isEmpty }
        XCTAssertTrue(opened)
        XCTAssertEqual(openedURLs, [try XCTUnwrap(tunnel.unambiguousBrowserURL)])
        XCTAssertEqual(store.phase(for: tunnel), .running)
        store.stop(tunnel)
    }

    func testStartProfilesMarkedForAutoStartStartsMarkedProfilesAndSkipsOthers() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)

        var marked = makeLocalProfile()
        marked.startsAtLaunch = true
        store.add(marked)
        let unmarked = makeGroupedProfile(
            name: "Stays stopped",
            port: 43_211,
            group: nil
        )
        store.add(unmarked)

        store.startProfilesMarkedForAutoStart()

        let finished = await waitUntil {
            if case .running = store.phase(for: marked) { return true }
            if case .failed = store.phase(for: marked) { return true }
            return false
        }
        guard finished else {
            return XCTFail("The marked profile never finished startup.")
        }
        guard store.phase(for: marked) == .running else {
            return XCTFail(
                "The marked profile did not start: \(store.phase(for: marked))"
            )
        }

        XCTAssertEqual(store.phase(for: unmarked), .stopped)
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL)),
            1
        )
        store.stopAll()
    }

    func testSetStartsAtLaunchPersistsWithoutChangingRunningPhase() async throws {
        let fixture = try makeFakeSSHFixture()
        defer { fixture.cleanup() }
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeFakeStore(defaults: defaults, fixture: fixture)
        let tunnel = makeLocalProfile()

        store.add(tunnel)
        store.start(tunnel)

        let finished = await waitUntil {
            if case .running = store.phase(for: tunnel) { return true }
            if case .failed = store.phase(for: tunnel) { return true }
            return false
        }
        guard finished, store.phase(for: tunnel) == .running else {
            return XCTFail(
                "The profile did not start: \(store.phase(for: tunnel))"
            )
        }

        store.setStartsAtLaunch(true, for: tunnel)

        XCTAssertTrue(store.tunnels[0].startsAtLaunch)
        XCTAssertEqual(store.phase(for: tunnel), .running)
        XCTAssertEqual(
            masterInvocationCount(try String(contentsOf: fixture.logURL)),
            1
        )

        let reloaded = TunnelStore.makeForTesting(defaults: defaults)
        XCTAssertTrue(reloaded.tunnels[0].startsAtLaunch)
        store.stopAll()
    }

    func testDecodesSavedProfilesWithoutAutoStartPreferenceAsFalse() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var tunnel = makeLocalProfile()
        tunnel.startsAtLaunch = true
        let encoded = try JSONEncoder().encode([tunnel])
        var objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        )
        for index in objects.indices {
            objects[index].removeValue(forKey: "startsAtLaunch")
        }
        defaults.set(
            try JSONSerialization.data(withJSONObject: objects),
            forKey: "savedTunnels.v2"
        )

        let store = TunnelStore.makeForTesting(defaults: defaults)

        XCTAssertEqual(store.tunnels.count, 1)
        XCTAssertFalse(store.tunnels[0].startsAtLaunch)
    }

    private func makeLocalProfile() -> Tunnel {
        Tunnel(
            name: "Web",
            localPort: 43_210,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: "example.com"
        )
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RelayBarTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeFakeStore(
        defaults: UserDefaults,
        fixture: FakeSSHFixture,
        maxRetryAttempts: Int = 1,
        retryDelay: TimeInterval = 0.01,
        retryDelayProvider: ((Int) -> TimeInterval)? = nil,
        browserOpener: @escaping (URL) -> Void = { _ in },
        failureNotifier: ((String, String) -> Void)? = nil,
        controlOperationTimeout: TimeInterval = 10,
        processTerminationGracePeriod: TimeInterval = 5,
        networkPathObserver: (any NetworkPathObserving)? = nil,
        networkChangeSettleDelay: TimeInterval = 0.01
    ) -> TunnelStore {
        // No unit test observes the real network: a store without an
        // injected observer gets an inert fake, never the system monitor.
        let observer: any NetworkPathObserving
        if let networkPathObserver {
            observer = networkPathObserver
        } else {
            observer = FakeNetworkPathObserver()
        }
        return TunnelStore(
            defaults: defaults,
            sshExecutableURL: fakeSSHURL,
            maxRetryAttempts: maxRetryAttempts,
            retryDelayProvider: retryDelayProvider ?? { _ in retryDelay },
            browserOpener: browserOpener,
            failureNotifier: failureNotifier,
            processEnvironment: fixture.environment,
            controlOperationTimeout: controlOperationTimeout,
            processTerminationGracePeriod: processTerminationGracePeriod,
            networkPathObserver: observer,
            networkChangeSettleDelay: networkChangeSettleDelay
        )
    }

    /// A file whose presence makes every fake master fail to connect, the
    /// way a VPN session makes the SSH host unreachable. Deleting it brings
    /// the network back.
    private func makeOutageMarker() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelayBarOutage-\(UUID().uuidString)")
        try Data().write(to: url)
        // Tests delete the marker to end the outage; a test that fails first
        // must not leave it behind.
        addTeardownBlock {
            _ = try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeGroupedProfile(
        name: String,
        port: Int,
        group: String?,
        sshHost: String = "example.com"
    ) -> Tunnel {
        Tunnel(
            name: name,
            localPort: port,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: sshHost,
            groupTag: group
        )
    }

    private func masterInvocationCount(_ log: String) -> Int {
        parsedInvocations(log).count { $0.contains("-M") }
    }

    /// Forward installs carrying one rule's specification. Masters cannot be
    /// told apart in the log — same host, same options — but each launch
    /// installs its own rules, so this attributes work to one profile.
    private func forwardInstallCount(_ log: String, spec: String) -> Int {
        parsedInvocations(log).count { $0.contains("forward") && $0.contains(spec) }
    }

    private var fakeSSHURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-ssh.sh")
    }

    private func makeFakeSSHFixture(
        overrides: [String: String] = [:]
    ) throws -> FakeSSHFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelayBarSSHTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let logURL = directory.appendingPathComponent("ssh.log")
        let counterURL = directory.appendingPathComponent("counter")
        try Data("47000\n".utf8).write(to: counterURL)
        var environment = [
            "RELAYBAR_FAKE_SSH_LOG": logURL.path,
            "RELAYBAR_FAKE_SSH_COUNTER": counterURL.path
        ]
        environment.merge(overrides) { _, replacement in replacement }
        return FakeSSHFixture(
            directory: directory,
            logURL: logURL,
            environment: environment
        )
    }

    private func waitUntil(
        timeoutIterations: Int = 400,
        condition: @escaping () -> Bool
    ) async -> Bool {
        for _ in 0..<timeoutIterations {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func parsedInvocations(_ log: String) -> [[String]] {
        var invocations: [[String]] = []
        var current: [String]?
        for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "BEGIN" {
                current = []
            } else if line == "END" {
                if let current { invocations.append(current) }
                current = nil
            } else if line.hasPrefix("ARG:"), current != nil {
                current?.append(String(line.dropFirst(4)))
            }
        }
        return invocations
    }
}

private struct FakeSSHFixture {
    let directory: URL
    let logURL: URL
    let environment: [String: String]

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension TunnelStore {
    /// A store for tests that never spins up the system path monitor. Every
    /// other construction in the test target injects the fake explicitly.
    static func makeForTesting(defaults: UserDefaults) -> TunnelStore {
        TunnelStore(defaults: defaults, networkPathObserver: FakeNetworkPathObserver())
    }
}

/// Stands in for the system path monitor so a test can fire a network path
/// change on demand — a VPN connecting or dropping — without a live network.
/// Every test store injects one, so no unit test observes the real network.
///
/// Two properties every test here relies on: observing delivers nothing by
/// itself, and only `simulateChange()` notifies. A store built with this
/// observer therefore sees exactly the changes its test fires.
@MainActor
final class FakeNetworkPathObserver: NetworkPathObserving {
    private var onChange: (@MainActor () -> Void)?

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        // The contract above holds only while the store subscribes once.
        if self.onChange != nil {
            XCTFail("The store subscribed to one observer twice.")
        }
        self.onChange = onChange
    }

    func simulateChange() {
        onChange?()
    }
}

/// Shared state a main-actor callback writes and the test reads, held in a
/// main-actor type rather than a captured local so the isolation is in the
/// type rather than in an assumption about the caller.
@MainActor
private final class ChangeCounter {
    var count = 0
}

/// The notification equivalent of `ChangeCounter`, for the same reason: the
/// store calls its notifier on the main actor, and this puts that in the
/// type instead of leaving it implicit in a captured local.
@MainActor
private final class NotificationLog {
    var entries: [(name: String, message: String)] = []
}

private struct LegacyTunnel: Codable {
    let id: UUID
    let name: String
    let localPort: Int
    let destinationHost: String
    let destinationPort: Int
    let sshHost: String
    let bindAddress: String?
    let additionalArguments: [String]
}
