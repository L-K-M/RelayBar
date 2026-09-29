import Foundation
import XCTest
@testable import RelayBar

final class RelayBarBackupCodecTests: XCTestCase {
    func testRoundTripPreservesProfilesAndHosts() throws {
        let contents = BackupFixtures.contents()

        let decoded = try RelayBarBackupCodec.decode(
            RelayBarBackupCodec.encode(contents, createdAt: BackupFixtures.date)
        )

        XCTAssertEqual(decoded, contents)
    }

    func testDocumentNamesItsFormatVersionAndCreationDate() throws {
        let data = try RelayBarBackupCodec.encode(
            BackupFixtures.contents(),
            createdAt: BackupFixtures.date
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["format"] as? String, "com.relaybarscion.backup")
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["createdAt"] as? String, "2026-09-29T10:00:05Z")
        XCTAssertEqual((object["profiles"] as? [Any])?.count, 2)
        XCTAssertEqual((object["remoteFilesHosts"] as? [Any])?.count, 1)
    }

    func testDigestIgnoresCreationDateButNotContents() throws {
        let contents = BackupFixtures.contents()
        var changed = contents
        changed.profiles[0].name = "Renamed"

        XCTAssertEqual(
            try RelayBarBackupCodec.digest(of: contents),
            try RelayBarBackupCodec.digest(of: BackupFixtures.contents())
        )
        XCTAssertNotEqual(
            try RelayBarBackupCodec.digest(of: contents),
            try RelayBarBackupCodec.digest(of: changed)
        )
    }

    func testRejectsFilesThatAreNotBackups() throws {
        let savedTunnelsBlob = try JSONEncoder().encode(
            BackupFixtures.contents().profiles
        )
        for data in [
            Data("not json".utf8),
            Data("{}".utf8),
            savedTunnelsBlob,
            Data(#"{"format":"com.example.other","version":1}"#.utf8),
            Data(#"{"format":"com.relaybarscion.backup","version":0}"#.utf8)
        ] {
            XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
                XCTAssertEqual(error as? RelayBarBackupError, .notABackup)
            }
        }
    }

    func testRejectsANewerVersion() throws {
        let data = try BackupFixtures.mutatedBackup { $0["version"] = 2 }

        XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? RelayBarBackupError, .newerVersion)
        }
    }

    func testRejectsAnOversizedFileBeforeParsing() {
        let data = Data(count: RelayBarBackupCodec.maximumFileSize + 1)

        XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? RelayBarBackupError, .tooLarge)
        }
    }

    func testRejectsAProfileTheSavedListWouldNotLoad() throws {
        let data = try BackupFixtures.mutatedBackup { document in
            var profiles = document["profiles"] as? [[String: Any]] ?? []
            profiles[0]["groupTag"] = String(repeating: "g", count: 33)
            document["profiles"] = profiles
        }

        XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
            guard case .damaged(let detail) = error as? RelayBarBackupError else {
                return XCTFail("Expected a damaged backup, got \(error)")
            }
            XCTAssertTrue(detail.contains("32 characters"), detail)
        }
    }

    func testRejectsRepeatedProfiles() throws {
        let data = try BackupFixtures.mutatedBackup { document in
            let profiles = document["profiles"] as? [[String: Any]] ?? []
            document["profiles"] = [profiles[0], profiles[0]]
        }

        XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
            XCTAssertEqual(
                error as? RelayBarBackupError,
                .damaged("It lists the same profile more than once.")
            )
        }
    }

    func testRejectsAnInvalidHost() throws {
        let data = try BackupFixtures.mutatedBackup { document in
            var hosts = document["remoteFilesHosts"] as? [[String: Any]] ?? []
            hosts[0]["sshHost"] = "-oProxyCommand=evil"
            document["remoteFilesHosts"] = hosts
        }

        XCTAssertThrowsError(try RelayBarBackupCodec.decode(data)) { error in
            guard case .damaged = error as? RelayBarBackupError else {
                return XCTFail("Expected a damaged backup, got \(error)")
            }
        }
    }

    func testRepeatedHostsCollapseToTheFirst() throws {
        var contents = BackupFixtures.contents()
        let first = contents.remoteFilesHosts[0]
        contents.remoteFilesHosts.append(
            BackupRemoteFilesHost(
                id: UUID(),
                name: "Same connection",
                sshHost: first.sshHost,
                additionalArguments: first.additionalArguments
            )
        )

        let decoded = try RelayBarBackupCodec.decode(
            RelayBarBackupCodec.encode(contents, createdAt: BackupFixtures.date)
        )

        XCTAssertEqual(decoded.remoteFilesHosts, [first])
    }
}

final class BackupFileNamingTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testAutomaticNamesCarryASortableSecondTimestamp() {
        let name = BackupFileNaming.automaticBackupName(
            for: BackupFixtures.date,
            timeZone: utc
        )

        XCTAssertEqual(name, "RelayBar Backup 2026-09-29 100005.json")
        XCTAssertTrue(BackupFileNaming.isAutomaticBackupName(name))
    }

    func testExportNamesAreNeverTakenForAutomaticBackups() {
        let name = BackupFileNaming.exportName(for: BackupFixtures.date, timeZone: utc)

        XCTAssertEqual(name, "RelayBar Export 2026-09-29.json")
        XCTAssertFalse(BackupFileNaming.isAutomaticBackupName(name))
    }

    func testOnlyExactAutomaticNamesMatch() {
        for name in [
            "RelayBar Backup 2026-09-29.json",
            "RelayBar Backup notes.json",
            "RelayBar Backup 2026-09-29 100005.json.bak",
            "Copy of RelayBar Backup 2026-09-29 100005.json",
            "RelayBar Backup 2026-09-29 100005 2.json"
        ] {
            XCTAssertFalse(BackupFileNaming.isAutomaticBackupName(name), name)
        }
    }

    func testPruningKeepsTheNewestAutomaticBackupsOnly() {
        let names = [
            "RelayBar Backup 2026-09-28 090000.json",
            "notes.txt",
            "RelayBar Backup 2026-09-29 100005.json",
            "RelayBar Export 2026-01-01.json",
            "RelayBar Backup 2026-09-27 235959.json"
        ]

        XCTAssertEqual(
            BackupFileNaming.automaticBackupNamesToPrune(names, keeping: 2),
            ["RelayBar Backup 2026-09-27 235959.json"]
        )
        XCTAssertEqual(
            BackupFileNaming.automaticBackupNamesToPrune(names, keeping: 5),
            []
        )
    }
}

final class BackupImportPreviewTests: XCTestCase {
    func testCountsWhatIsNotSavedYet() {
        let backup = BackupFixtures.contents()
        let current = RelayBarBackupContents(
            profiles: [backup.profiles[0]],
            remoteFilesHosts: [
                // Same connection under a different identity still counts
                // as saved: the catalog keeps one record per connection.
                BackupRemoteFilesHost(
                    id: UUID(),
                    name: "Renamed",
                    sshHost: backup.remoteFilesHosts[0].sshHost,
                    additionalArguments: backup.remoteFilesHosts[0].additionalArguments
                )
            ]
        )

        let preview = BackupImportPreview(importing: backup, into: current)

        XCTAssertEqual(preview.profileCount, 2)
        XCTAssertEqual(preview.remoteFilesHostCount, 1)
        XCTAssertEqual(preview.missingProfileCount, 1)
        XCTAssertEqual(preview.missingRemoteFilesHostCount, 0)
        XCTAssertTrue(preview.hasMissingItems)
    }

    func testConfirmationExplainsBothChoicesAndPluralizes() {
        let backup = BackupFixtures.contents()
        let preview = BackupImportPreview(
            importing: backup,
            into: RelayBarBackupContents(profiles: [backup.profiles[0]], remoteFilesHosts: [])
        )

        XCTAssertEqual(
            BackupCopy.importInformativeText(for: preview),
            "This backup has 2 profiles and 1 Remote Files host. "
                + "1 profile and 1 Remote Files host aren't in RelayBar yet.\n\n"
                + "Add Missing adds only those and leaves everything you have unchanged. "
                + "Replace All removes every saved profile and Remote Files host "
                + "that isn't in the backup, restores the backup's version of the rest, "
                + "and stops any active tunnels."
        )
    }

    func testConfirmationWithNothingMissingOffersOnlyReplacement() {
        let backup = BackupFixtures.contents()
        let preview = BackupImportPreview(importing: backup, into: backup)

        XCTAssertFalse(preview.hasMissingItems)
        XCTAssertTrue(
            BackupCopy.importInformativeText(for: preview).hasPrefix(
                "This backup has 2 profiles and 1 Remote Files host, "
                    + "and you already have all of them."
            )
        )
        XCTAssertFalse(
            BackupCopy.importInformativeText(for: preview).contains("Add Missing")
        )
    }

    func testResultTextNamesWhatChanged() {
        XCTAssertEqual(
            BackupCopy.importResultText(
                BackupImportResult(profileCount: 1, remoteFilesHostCount: 0),
                mode: .addMissing
            ),
            "Added 1 profile and 0 Remote Files hosts."
        )
        XCTAssertEqual(
            BackupCopy.importResultText(
                BackupImportResult(profileCount: 3, remoteFilesHostCount: 2),
                mode: .replaceAll
            ),
            "Restored 3 profiles and 2 Remote Files hosts from the backup."
        )
    }
}

@MainActor
final class BackupImportTargetTests: XCTestCase {
    func testAddMissingAppendsOnlyUnsavedProfilesAndJoinsExistingGroups() {
        let (defaults, suiteName) = BackupFixtures.isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        let saved = BackupFixtures.profile(name: "Saved", groupTag: "Work")
        store.add(saved)

        var changedCopy = saved
        changedCopy.name = "Changed in the backup"
        let newProfile = BackupFixtures.profile(name: "New", groupTag: "work")

        let added = store.importProfiles([changedCopy, newProfile], mode: .addMissing)

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.tunnels.map(\.name), ["Saved", "New"])
        XCTAssertEqual(store.tunnels.map(\.groupTag), ["Work", "Work"])
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertEqual(
            TunnelStore.makeForTesting(defaults: defaults).tunnels.map(\.name),
            ["Saved", "New"]
        )
    }

    func testReplaceAllMakesTheSavedListTheBackupsAndClearsStalePhases() {
        let (defaults, suiteName) = BackupFixtures.isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore.makeForTesting(defaults: defaults)
        let kept = BackupFixtures.profile(name: "Kept")
        let removed = BackupFixtures.profile(name: "Removed")
        store.add(kept)
        store.add(removed)
        store.setPreviewPhase(.failed("Old failure"), for: kept)

        var restored = kept
        restored.name = "Kept, restored"
        let added = BackupFixtures.profile(name: "Added")

        let count = store.importProfiles([restored, added], mode: .replaceAll)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.tunnels, [restored, added])
        XCTAssertEqual(store.phase(for: restored), .stopped)
        XCTAssertEqual(
            TunnelStore.makeForTesting(defaults: defaults).tunnels,
            [restored, added]
        )
    }

    func testHostAddMissingSkipsSavedConnectionsAndInvalidHosts() throws {
        let (defaults, suiteName) = BackupFixtures.isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = RemoteServerCatalog(defaults: defaults)
        let saved = try catalog.add(name: "Build", sshHost: "build.example.com")

        let added = catalog.importSavedHosts(
            [
                BackupRemoteFilesHost(
                    id: UUID(),
                    name: "Build again",
                    sshHost: saved.sshHost,
                    additionalArguments: []
                ),
                BackupRemoteFilesHost(
                    id: UUID(),
                    name: "Invalid",
                    sshHost: "-oProxyCommand=evil",
                    additionalArguments: []
                ),
                BackupRemoteFilesHost(
                    id: UUID(),
                    name: "Media",
                    sshHost: "media.example.com",
                    additionalArguments: []
                )
            ],
            mode: .addMissing
        )

        XCTAssertEqual(added, 1)
        XCTAssertEqual(catalog.savedHostsForBackup.map(\.name), ["Build", "Media"])
        XCTAssertEqual(
            RemoteServerCatalog(defaults: defaults).savedHostsForBackup.map(\.name),
            ["Build", "Media"]
        )
    }

    func testHostReplaceAllKeepsRecentHistory() throws {
        let (defaults, suiteName) = BackupFixtures.isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = RemoteServerCatalog(defaults: defaults)
        let saved = try catalog.add(name: "Build", sshHost: "build.example.com")
        catalog.recordSuccessfulOpen(saved)
        let replacement = BackupRemoteFilesHost(
            id: UUID(),
            name: "Media",
            sshHost: "media.example.com",
            additionalArguments: []
        )

        let count = catalog.importSavedHosts([replacement], mode: .replaceAll)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(catalog.savedHostsForBackup, [replacement])
        XCTAssertTrue(
            catalog.servers(from: []).contains {
                $0.source == .recent && $0.sshHost == "build.example.com"
            }
        )
    }

    func testHostImportRespectsTheSavedHostLimit() {
        let (defaults, suiteName) = BackupFixtures.isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = RemoteServerCatalog(defaults: defaults)
        let hosts = (0..<130).map { index in
            BackupRemoteFilesHost(
                id: UUID(),
                name: "Host \(index)",
                sshHost: "host-\(index).example.com",
                additionalArguments: []
            )
        }

        XCTAssertEqual(catalog.importSavedHosts(hosts, mode: .addMissing), 128)
        XCTAssertEqual(catalog.savedHostsForBackup.count, 128)
    }
}

@MainActor
final class BackupModelTests: XCTestCase {
    func testAutomaticBackupsAreOffUntilEnabled() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }

        fixture.model.performAutomaticBackupIfNeeded()

        XCTAssertFalse(fixture.model.isAutomaticBackupEnabled)
        XCTAssertEqual(try fixture.backupNames(), [])
    }

    func testEnablingWithoutAFolderAsksForOneAndCancellingKeepsItOff() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }

        fixture.model.setAutomaticBackupEnabled(true)

        XCTAssertEqual(fixture.presenter.folderRequests, 1)
        XCTAssertFalse(fixture.model.isAutomaticBackupEnabled)
        XCTAssertNil(fixture.model.folder)
    }

    func testEnablingWritesAnOwnerOnlyBackupAndPersistsTheSetting() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        fixture.presenter.folderChoice = fixture.folder

        fixture.model.setAutomaticBackupEnabled(true)

        XCTAssertTrue(fixture.model.isAutomaticBackupEnabled)
        XCTAssertNil(fixture.model.automaticBackupError)
        XCTAssertEqual(fixture.model.lastAutomaticBackupDate, fixture.clock.date)
        let names = try fixture.backupNames()
        XCTAssertEqual(names.count, 1)
        let url = fixture.folder.appendingPathComponent(names[0])
        XCTAssertEqual(
            try RelayBarBackupCodec.decode(Data(contentsOf: url)),
            fixture.dataSource.contents
        )
        let permissions = try FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let restored = fixture.makeModel()
        XCTAssertTrue(restored.isAutomaticBackupEnabled)
        XCTAssertEqual(restored.folder?.path, fixture.model.folder?.path)
        XCTAssertEqual(restored.lastAutomaticBackupDate, fixture.clock.date)
    }

    func testWritesOnlyWhenTheContentsChange() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        fixture.presenter.folderChoice = fixture.folder
        fixture.model.setAutomaticBackupEnabled(true)

        fixture.clock.advance(by: 5)
        fixture.model.performAutomaticBackupIfNeeded()
        XCTAssertEqual(try fixture.backupNames().count, 1)

        fixture.dataSource.contents.profiles[0].name = "Renamed"
        fixture.model.performAutomaticBackupIfNeeded()
        XCTAssertEqual(try fixture.backupNames().count, 2)
    }

    func testNeverBacksUpAnEmptyList() throws {
        let fixture = try BackupModelFixture(
            contents: RelayBarBackupContents(profiles: [], remoteFilesHosts: [])
        )
        defer { fixture.tearDown() }
        fixture.presenter.folderChoice = fixture.folder

        fixture.model.setAutomaticBackupEnabled(true)

        XCTAssertTrue(fixture.model.isAutomaticBackupEnabled)
        XCTAssertEqual(try fixture.backupNames(), [])
    }

    func testMissingFolderIsReportedAndRetriedLater() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let missing = fixture.folder.appendingPathComponent("Unmounted", isDirectory: true)
        fixture.presenter.folderChoice = missing

        fixture.model.setAutomaticBackupEnabled(true)

        XCTAssertEqual(
            fixture.model.automaticBackupError,
            RelayBarBackupError.folderMissing("Unmounted").errorDescription
        )
        XCTAssertNil(fixture.model.lastAutomaticBackupDate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
        fixture.model.performAutomaticBackupIfNeeded()

        XCTAssertNil(fixture.model.automaticBackupError)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: missing.path).count,
            1
        )
    }

    func testRetentionPrunesOnlyOldAutomaticBackupFiles() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let manager = FileManager.default
        let calendar = Calendar(identifier: .gregorian)
        for day in 1...35 {
            let date = calendar.date(
                byAdding: .day,
                value: -day,
                to: fixture.clock.date
            )!
            let name = BackupFileNaming.automaticBackupName(for: date)
            try Data("old".utf8).write(to: fixture.folder.appendingPathComponent(name))
        }
        let unrelated = fixture.folder.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let lookalikeFolder = fixture.folder.appendingPathComponent(
            BackupFileNaming.automaticBackupName(for: Date(timeIntervalSince1970: 0)),
            isDirectory: true
        )
        try manager.createDirectory(at: lookalikeFolder, withIntermediateDirectories: false)
        fixture.presenter.folderChoice = fixture.folder

        fixture.model.setAutomaticBackupEnabled(true)

        let backups = try fixture.backupNames().filter {
            !isDirectory(fixture.folder.appendingPathComponent($0))
        }
        XCTAssertEqual(backups.count, BackupFileNaming.retainedAutomaticBackupCount)
        XCTAssertTrue(
            backups.contains(BackupFileNaming.automaticBackupName(for: fixture.clock.date))
        )
        XCTAssertTrue(manager.fileExists(atPath: unrelated.path))
        XCTAssertTrue(isDirectory(lookalikeFolder))
    }

    func testExportWritesTheChosenFileAndReportsWhatItContains() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let destination = fixture.folder.appendingPathComponent("Exported.json")
        fixture.presenter.exportDestination = destination

        fixture.model.exportBackup()

        XCTAssertEqual(
            fixture.presenter.suggestedExportNames,
            [BackupFileNaming.exportName(for: fixture.clock.date)]
        )
        XCTAssertEqual(
            try RelayBarBackupCodec.decode(Data(contentsOf: destination)),
            fixture.dataSource.contents
        )
        XCTAssertEqual(
            fixture.model.activity,
            .succeeded("Exported 2 profiles and 1 Remote Files host.")
        )

        fixture.model.cancelTransientState()
        XCTAssertEqual(fixture.model.activity, .idle)
    }

    func testCancelledExportChangesNothing() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }

        fixture.model.exportBackup()

        XCTAssertEqual(fixture.model.activity, .idle)
        XCTAssertEqual(try fixture.backupNames(), [])
    }

    func testImportAppliesTheChosenModeAfterConfirmation() throws {
        let fixture = try BackupModelFixture(
            contents: RelayBarBackupContents(profiles: [], remoteFilesHosts: [])
        )
        defer { fixture.tearDown() }
        let backup = BackupFixtures.contents()
        let file = fixture.folder.appendingPathComponent("Backup.json")
        try RelayBarBackupCodec.encode(backup, createdAt: fixture.clock.date).write(to: file)
        fixture.presenter.importFile = file
        fixture.presenter.importDecision = .addMissing

        fixture.model.importBackup()

        XCTAssertEqual(fixture.presenter.confirmedFileNames, ["Backup.json"])
        XCTAssertEqual(fixture.presenter.confirmedPreviews.first?.missingProfileCount, 2)
        XCTAssertEqual(fixture.dataSource.imports.map { $0.mode }, [.addMissing])
        XCTAssertEqual(fixture.dataSource.imports.first?.contents, backup)
        XCTAssertEqual(
            fixture.model.activity,
            .succeeded("Added 2 profiles and 1 Remote Files host.")
        )
    }

    func testCancelledImportConfirmationImportsNothing() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let file = fixture.folder.appendingPathComponent("Backup.json")
        try RelayBarBackupCodec.encode(BackupFixtures.contents(), createdAt: fixture.clock.date)
            .write(to: file)
        fixture.presenter.importFile = file

        fixture.model.importBackup()

        XCTAssertEqual(fixture.presenter.confirmedFileNames, ["Backup.json"])
        XCTAssertTrue(fixture.dataSource.imports.isEmpty)
        XCTAssertEqual(fixture.model.activity, .idle)
    }

    func testImportOfAnUnreadableFileNamesTheFileAndTheReason() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let file = fixture.folder.appendingPathComponent("Other.json")
        try Data("[]".utf8).write(to: file)
        fixture.presenter.importFile = file

        fixture.model.importBackup()

        XCTAssertTrue(fixture.presenter.confirmedFileNames.isEmpty)
        XCTAssertTrue(fixture.dataSource.imports.isEmpty)
        XCTAssertEqual(
            fixture.model.activity,
            .failed("Couldn't import \u{201c}Other.json\u{201d}. The file isn't a RelayBar backup.")
        )
    }

    func testImportBacksUpWhatItReplacesFirst() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        fixture.presenter.folderChoice = fixture.folder
        fixture.model.setAutomaticBackupEnabled(true)

        // A change still inside the settle delay when the import starts.
        fixture.clock.advance(by: 1)
        fixture.dataSource.contents.profiles[0].name = "Unsaved edit"
        let beforeImport = fixture.dataSource.contents

        let file = fixture.folder.appendingPathComponent("Other backup.json")
        try RelayBarBackupCodec.encode(
            RelayBarBackupContents(
                profiles: [BackupFixtures.profile(name: "Imported")],
                remoteFilesHosts: []
            ),
            createdAt: fixture.clock.date
        ).write(to: file)
        fixture.presenter.importFile = file
        fixture.presenter.importDecision = .replaceAll
        fixture.clock.advance(by: 1)

        fixture.model.importBackup()

        let newest = try XCTUnwrap(try fixture.backupNames().last)
        XCTAssertEqual(
            try RelayBarBackupCodec.decode(
                Data(contentsOf: fixture.folder.appendingPathComponent(newest))
            ),
            beforeImport
        )
        XCTAssertEqual(fixture.dataSource.imports.map { $0.mode }, [.replaceAll])
    }

    func testStoreBackupRoundTripsThroughAFileIntoAFreshInstall() throws {
        let fixture = try BackupModelFixture()
        defer { fixture.tearDown() }
        let (sourceDefaults, sourceSuite) = BackupFixtures.isolatedDefaults()
        let (targetDefaults, targetSuite) = BackupFixtures.isolatedDefaults()
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }
        let sourceStore = TunnelStore.makeForTesting(defaults: sourceDefaults)
        let sourceCatalog = RemoteServerCatalog(defaults: sourceDefaults)
        for profile in BackupFixtures.contents().profiles {
            sourceStore.add(profile)
        }
        _ = try sourceCatalog.add(name: "Build", sshHost: "build.example.com")
        let destination = fixture.folder.appendingPathComponent("Move.json")
        fixture.presenter.exportDestination = destination
        let exporter = fixture.makeModel(
            dataSource: StoreBackupDataSource(store: sourceStore, catalog: sourceCatalog)
        )
        exporter.exportBackup()

        let targetStore = TunnelStore.makeForTesting(defaults: targetDefaults)
        let targetCatalog = RemoteServerCatalog(defaults: targetDefaults)
        var refreshCount = 0
        let importer = fixture.makeModel(
            dataSource: StoreBackupDataSource(
                store: targetStore,
                catalog: targetCatalog,
                savedHostsDidChange: { refreshCount += 1 }
            )
        )
        fixture.presenter.importFile = destination
        fixture.presenter.importDecision = .replaceAll
        importer.importBackup()

        XCTAssertEqual(targetStore.tunnels, sourceStore.tunnels)
        XCTAssertEqual(targetCatalog.savedHostsForBackup, sourceCatalog.savedHostsForBackup)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(
            importer.activity,
            .succeeded("Restored 2 profiles and 1 Remote Files host from the backup.")
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

enum BackupFixtures {
    /// 2026-09-29T10:00:05Z.
    static let date = Date(timeIntervalSince1970: 1_790_676_005)

    static func profile(name: String, groupTag: String? = nil) -> Tunnel {
        Tunnel(
            name: name,
            localPort: 8_080,
            destinationHost: "localhost",
            destinationPort: 3_000,
            sshHost: "dev@example.com",
            groupTag: groupTag
        )
    }

    static func contents() -> RelayBarBackupContents {
        var web = profile(name: "Web", groupTag: "Work")
        web.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        web.rules[0].id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        web.startsAtLaunch = true
        web.openOnConnectURL = "http://localhost:8080/dashboard"
        let socks = Tunnel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "SOCKS",
            sshHost: "bastion.example.com",
            additionalArguments: ["-p", "2222"],
            rules: [
                ForwardingRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
                    kind: .localDynamic,
                    listen: .tcp(bindAddress: "localhost", port: 1_080)
                )
            ]
        )
        return RelayBarBackupContents(
            profiles: [web, socks],
            remoteFilesHosts: [
                BackupRemoteFilesHost(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                    name: "Build",
                    sshHost: "build.example.com",
                    additionalArguments: []
                )
            ]
        )
    }

    static func mutatedBackup(
        _ transform: (inout [String: Any]) -> Void
    ) throws -> Data {
        let data = try RelayBarBackupCodec.encode(contents(), createdAt: date)
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        transform(&document)
        return try JSONSerialization.data(withJSONObject: document)
    }

    static func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RelayBarTests.Backup.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

@MainActor
final class BackupModelFixture {
    final class Clock {
        var date = BackupFixtures.date

        func advance(by seconds: TimeInterval) {
            date = date.addingTimeInterval(seconds)
        }
    }

    let folder: URL
    let defaults: UserDefaults
    let suiteName: String
    let clock = Clock()
    let dataSource: StaticBackupDataSource
    let presenter = ScriptedBackupPanelPresenter()
    private(set) var model: BackupModel!

    init(contents: RelayBarBackupContents = BackupFixtures.contents()) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RelayBarBackupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let isolated = BackupFixtures.isolatedDefaults()
        defaults = isolated.0
        suiteName = isolated.1
        dataSource = StaticBackupDataSource(contents: contents)
        model = makeModel()
    }

    func makeModel(dataSource: (any BackupDataSource)? = nil) -> BackupModel {
        let clock = clock
        return BackupModel(
            dataSource: dataSource ?? self.dataSource,
            presenter: presenter,
            defaults: defaults,
            now: { clock.date }
        )
    }

    /// Automatic backup names in the folder, oldest first.
    func backupNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter(BackupFileNaming.isAutomaticBackupName)
            .sorted()
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Saved work held in memory; an import replaces or extends it the way the
/// real stores would, and is recorded for assertions.
@MainActor
final class StaticBackupDataSource: BackupDataSource {
    var contents: RelayBarBackupContents
    private(set) var imports: [(contents: RelayBarBackupContents, mode: BackupImportMode)] = []

    init(
        contents: RelayBarBackupContents = RelayBarBackupContents(
            profiles: [],
            remoteFilesHosts: []
        )
    ) {
        self.contents = contents
    }

    func currentBackupContents() -> RelayBarBackupContents {
        contents
    }

    func importBackupContents(
        _ imported: RelayBarBackupContents,
        mode: BackupImportMode
    ) -> BackupImportResult {
        imports.append((imported, mode))
        switch mode {
        case .addMissing:
            contents.profiles += imported.profiles
            contents.remoteFilesHosts += imported.remoteFilesHosts
        case .replaceAll:
            contents = imported
        }
        return BackupImportResult(
            profileCount: imported.profiles.count,
            remoteFilesHostCount: imported.remoteFilesHosts.count
        )
    }
}

/// Answers every panel with a scripted value; `nil` stands for Cancel.
@MainActor
final class ScriptedBackupPanelPresenter: BackupPanelPresenting {
    var folderChoice: URL?
    var exportDestination: URL?
    var importFile: URL?
    var importDecision: BackupImportMode?
    private(set) var folderRequests = 0
    private(set) var suggestedExportNames: [String] = []
    private(set) var confirmedPreviews: [BackupImportPreview] = []
    private(set) var confirmedFileNames: [String] = []

    func chooseBackupFolder(current: URL?) -> URL? {
        folderRequests += 1
        return folderChoice
    }

    func chooseExportDestination(suggestedName: String) -> URL? {
        suggestedExportNames.append(suggestedName)
        return exportDestination
    }

    func chooseImportFile() -> URL? {
        importFile
    }

    func confirmImport(_ preview: BackupImportPreview, fileName: String) -> BackupImportMode? {
        confirmedPreviews.append(preview)
        confirmedFileNames.append(fileName)
        return importDecision
    }
}
