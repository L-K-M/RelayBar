// Renders the menu window offscreen so a change to the saved list can be
// reviewed in both appearances without a screen-capture permission. Skipped
// unless RELAYBAR_SNAPSHOT_DIR is set, following the opt-in pattern the live
// SSH tests use.
import AppKit
import SwiftUI
import XCTest
@testable import RelayBar

@MainActor
final class VisualSnapshotHarness: XCTestCase {
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] ?? "")
    }

    func testCaptureTunnelListSnapshots() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        let suiteName = "RelayBarSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TunnelStore(defaults: defaults)

        let fixtures: [(name: String, group: String?)] = [
            ("Hermes Dashboard", "Work"),
            ("Virtual Desktop", "Work"),
            ("Photos", "Personal"),
            ("Scratch", nil)
        ]
        for (index, fixture) in fixtures.enumerated() {
            store.add(
                Tunnel(
                    name: fixture.name,
                    localPort: 8_000 + index,
                    destinationHost: "localhost",
                    destinationPort: 3_000 + index,
                    sshHost: "preview-\(index + 1).example.com",
                    groupTag: fixture.group
                )
            )
        }

        // A local Unix-socket rule exercises the Task 014 Reveal path.
        store.add(
            Tunnel(
                name: "Socket Forward",
                sshHost: "gateway.example.com",
                rules: [
                    ForwardingRule(
                        kind: .local,
                        listen: .unix(path: "/tmp/relaybar-visual.sock"),
                        destination: .tcp(host: "localhost", port: 5_432)
                    )
                ],
                groupTag: "Work"
            )
        )

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            let listURL = outputDirectory.appendingPathComponent(
                "tunnel-list-\(label).png"
            )
            try capture(
                view: RelayBarRootView(
                    loginItemService: LoginItemServiceSpy(status: .enabled),
                    updateModel: previewUpdateModel()
                )
                .environmentObject(store),
                appearance: appearanceName,
                to: listURL
            )
            let listWithUpdateStateURL = outputDirectory.appendingPathComponent(
                "tunnel-list-update-state-\(label).png"
            )
            try capture(
                view: RelayBarRootView(
                    loginItemService: LoginItemServiceSpy(status: .enabled),
                    updateModel: previewUpdateModel(result: .upToDate)
                )
                .environmentObject(store),
                appearance: appearanceName,
                to: listWithUpdateStateURL
            )
            XCTAssertEqual(
                try Data(contentsOf: listURL),
                try Data(contentsOf: listWithUpdateStateURL),
                "Updater state must not change the tunnel list or Settings button."
            )
            try capture(
                view: SettingsView(
                    launchAtLogin: LaunchAtLoginModel(
                        service: LoginItemServiceSpy(status: .enabled)
                    ),
                    updates: previewUpdateModel(),
                    about: previewAboutModel(),
                    onBack: {}
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent("settings-\(label).png")
            )
            try capture(
                view: SettingsView(
                    launchAtLogin: LaunchAtLoginModel(
                        service: LoginItemServiceSpy(status: .enabled)
                    ),
                    updates: previewUpdateModel(result: .upToDate),
                    about: previewAboutModel(copied: true),
                    onBack: {}
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent(
                    "settings-transient-confirmations-\(label).png"
                )
            )
            // The approval-required caption is the tallest Launch at Login
            // variant; capture it to verify the card's second row.
            try capture(
                view: SettingsView(
                    launchAtLogin: LaunchAtLoginModel(
                        service: LoginItemServiceSpy(status: .requiresApproval)
                    ),
                    updates: previewUpdateModel(),
                    about: previewAboutModel(),
                    onBack: {}
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent(
                    "settings-login-approval-\(label).png"
                )
            )
        }
    }

    private func previewUpdateModel(
        result: UpdateCheckResult? = nil
    ) -> UpdateModel {
        let service = SnapshotUpdateService()
        let model = UpdateModel(
            service: service,
            announcer: SnapshotAccessibilityAnnouncer()
        )
        if let result {
            model.checkForUpdates()
            service.complete(with: result)
        }
        return model
    }

    private func previewAboutModel(copied: Bool = false) -> ApplicationAboutModel {
        let model = ApplicationAboutModel(
            metadata: ApplicationMetadata(
                infoDictionary: [
                    "CFBundleName": "RelayBar",
                    "CFBundleShortVersionString": "1.3.0",
                    "CFBundleVersion": "6"
                ]
            ),
            pasteboardWriter: SnapshotPasteboardWriter(),
            announcer: SnapshotAccessibilityAnnouncer(),
            confirmationDuration: .seconds(30)
        )
        if copied { model.copyVersion() }
        return model
    }

    func testCaptureTask021Snapshots() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        let catalog = RemoteServerCatalog()
        _ = try catalog.add(name: "Development server", sshHost: "devbox.local")
        let remoteFilesModel = RemoteFilesModel(
            tunnels: [],
            serverCatalog: catalog
        )
        let editTunnel = Tunnel(
            name: "PostgreSQL through bastion",
            localPort: 5_432,
            destinationHost: "database.internal",
            destinationPort: 5_432,
            sshHost: "developer@bastion.example.com",
            groupTag: "Work"
        )

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            try capture(
                view: TunnelEditorView(
                    tunnel: nil,
                    availableGroups: ["Personal", "Work"],
                    onCancel: {},
                    onSave: { _ in }
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                size: NSSize(width: 380, height: 440),
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent(
                    "task-021-new-profile-\(label).png"
                )
            )
            try capture(
                view: TunnelEditorView(
                    tunnel: editTunnel,
                    availableGroups: ["Personal", "Work"],
                    onCancel: {},
                    onSave: { _ in }
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                size: NSSize(width: 380, height: 440),
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent(
                    "task-031-edit-profile-\(label).png"
                )
            )
            try capture(
                view: RemoteFilesView(model: remoteFilesModel),
                appearance: appearanceName,
                size: NSSize(width: 360, height: 300),
                to: outputDirectory.appendingPathComponent(
                    "task-021-remote-files-\(label).png"
                )
            )
        }
    }

    func testCaptureTask025Snapshots() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            try capture(
                view: TunnelEditorView(
                    tunnel: nil,
                    availableGroups: ["Personal", "Work"],
                    onCancel: {},
                    onSave: { _ in }
                )
                .background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearanceName,
                size: NSSize(width: 380, height: 440),
                scrollOffsetY: 300,
                assertHorizontalContainment: true,
                to: outputDirectory.appendingPathComponent(
                    "task-025-rule-type-\(label).png"
                )
            )
        }
    }

    func testCaptureTask026Snapshots() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            let service = Task026SnapshotService()
            let output = RemoteFileEntry(
                name: "output",
                path: "/srv/app/output",
                kind: .directory,
                size: nil,
                modificationText: "Jul 29 12:00"
            )
            let report = RemoteFileEntry(
                name: "report.md",
                path: "/srv/app/output/report.md",
                kind: .file,
                size: 8_420,
                modificationText: "Jul 29 12:01"
            )
            service.setListing([output], for: "/srv/app")
            service.setListing([report], for: output.path)
            let tunnel = Tunnel(
                name: "Development",
                localPort: 8_080,
                destinationHost: "localhost",
                destinationPort: 3_000,
                sshHost: "devbox.local"
            )
            let model = RemoteFilesModel(
                tunnels: [tunnel],
                service: service,
                serverCatalog: RemoteServerCatalog()
            )
            model.remotePath = "/srv/app"
            model.openRemotePath()
            try await waitUntil {
                model.screen == .browser && !model.isLoading
            }

            service.setSuspended(true, for: output.path)
            model.activate(output)
            XCTAssertTrue(model.isLoading)
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: NSSize(width: 780, height: 520),
                to: outputDirectory.appendingPathComponent(
                    "task-026-opening-\(label).png"
                )
            )

            model.goBack()
            service.setSuspended(false, for: output.path)
            model.activate(output)
            try await waitUntil {
                model.currentPath == output.path && !model.isLoading
            }

            service.setSuspended(true, for: "/srv/app")
            model.goBack()
            XCTAssertTrue(model.isRefreshing)
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: NSSize(width: 780, height: 520),
                to: outputDirectory.appendingPathComponent(
                    "task-026-cached-refresh-\(label).png"
                )
            )

            service.setError(
                RemoteFileError.commandFailed("The connection was lost."),
                for: "/srv/app"
            )
            service.setSuspended(false, for: "/srv/app")
            try await waitUntil {
                model.errorMessage == "The connection was lost."
                    && !model.isRefreshing
            }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: NSSize(width: 780, height: 520),
                to: outputDirectory.appendingPathComponent(
                    "task-026-revalidation-failure-\(label).png"
                )
            )
            model.cancelAll()
        }
    }

    func testCaptureTask037RemoteFilesWorkspaceSnapshots() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        let entries = [
            RemoteFileEntry(
                name: "builds",
                path: "/srv/releases/builds",
                kind: .directory,
                size: nil,
                modificationText: "Aug 24 14:08"
            ),
            RemoteFileEntry(
                name: "README.md",
                path: "/srv/releases/README.md",
                kind: .file,
                size: 8_420,
                modificationText: "Aug 24 13:42"
            ),
            RemoteFileEntry(
                name: "release.zip",
                path: "/srv/releases/release.zip",
                kind: .file,
                size: 3_842_100,
                modificationText: "Aug 24 13:40"
            )
        ]

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            let fixture = try task037WorkspaceFixture(entries: entries)
            let model = fixture.model
            let recentHostID = try XCTUnwrap(model.servers(from: .recent).first?.id)
            let firstLocationID = try XCTUnwrap(model.recentLocations.first?.id)

            try capture(
                view: RemoteFilesView(
                    model: model,
                    expandedHostIDs: [recentHostID],
                    initialFocusedSidebarItem: .location(firstLocationID)
                ),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-keyboard-focus-\(label).png"
                )
            )

            let longPathFixture = try task037WorkspaceFixture(entries: entries)
            let longLocation = try XCTUnwrap(
                longPathFixture.model.recentLocations.first(where: {
                    $0.path.contains("a-very-long-project-name")
                })
            )
            longPathFixture.model.activate(longLocation)
            try await waitUntil {
                longPathFixture.model.screen == .browser
                    && !longPathFixture.model.isLoading
            }
            try capture(
                view: RemoteFilesView(model: longPathFixture.model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.browserMinimum,
                to: outputDirectory.appendingPathComponent(
                    "task-037-long-path-\(label).png"
                ),
            )
            longPathFixture.model.cancelAll()

            try capture(
                view: RemoteFilesView(
                    model: model,
                    expandedHostIDs: [recentHostID]
                ),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-welcome-expanded-host-\(label).png"
                )
            )

            model.activate(try XCTUnwrap(model.recentLocations.first))
            try await waitUntil { model.screen == .browser && !model.isLoading }
            try capture(
                view: RemoteFilesView(
                    model: model,
                    expandedHostIDs: [recentHostID]
                ),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-folder-\(label).png"
                )
            )
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.browserMinimum,
                to: outputDirectory.appendingPathComponent(
                    "task-037-narrow-\(label).png"
                )
            )

            let uploadDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RelayBarTask037-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: uploadDirectory,
                withIntermediateDirectories: false
            )
            defer { try? FileManager.default.removeItem(at: uploadDirectory) }
            let uploadFile = uploadDirectory.appendingPathComponent("notes.txt")
            try Data("release notes".utf8).write(to: uploadFile)
            fixture.presenter.uploadFile = uploadFile
            fixture.service.setUploadSuspended(true)
            model.beginUpload()
            try await waitUntil { model.upload?.phase == .active }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-upload-progress-\(label).png"
                )
            )
            model.cancelUpload()
            try await waitUntil { model.upload?.phase == .cancelled }
            fixture.service.setUploadSuspended(false)
            model.dismissUpload()

            let markdownDirectory = uploadDirectory.appendingPathComponent("preview")
            try FileManager.default.createDirectory(
                at: markdownDirectory,
                withIntermediateDirectories: false
            )
            let markdownURL = markdownDirectory.appendingPathComponent("README.md")
            try Data("# Release workspace\n\nPreview remains beside recent locations.".utf8)
                .write(to: markdownURL)
            fixture.service.previewURL = markdownURL
            model.preview(entries[1])
            try await waitUntil { model.previewMarkdown != nil }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.previewPreferred,
                to: outputDirectory.appendingPathComponent(
                    "task-037-preview-\(label).png"
                )
            )
            model.closePreview()

            fixture.presenter.uploadFile = uploadFile
            fixture.service.uploadError = RemoteFileError.uploadConflict
            model.beginUpload()
            try await waitUntil {
                model.upload?.phase == .failed && !model.isRefreshing
            }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-upload-conflict-\(label).png"
                )
            )
            model.cancelAll()

            let emptyModel = RemoteFilesModel(
                tunnels: [],
                serverCatalog: RemoteServerCatalog()
            )
            try capture(
                view: RemoteFilesView(model: emptyModel),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-empty-history-\(label).png"
                )
            )
            emptyModel.remotePath = "relative/path"
            try capture(
                view: AddRemotePathView(model: emptyModel),
                appearance: appearanceName,
                size: NSSize(width: 430, height: 360),
                to: outputDirectory.appendingPathComponent(
                    "task-037-add-path-validation-\(label).png"
                )
            )

            let failedFixture = try task037WorkspaceFixture(entries: entries)
            let failedPath = try XCTUnwrap(failedFixture.model.recentLocations.first).path
            failedFixture.service.setError(
                RemoteFileError.commandFailed("The remote path wasn’t found."),
                for: failedPath
            )
            failedFixture.model.activate(
                try XCTUnwrap(failedFixture.model.recentLocations.first)
            )
            try await waitUntil { failedFixture.model.failedLocationID != nil }
            try capture(
                view: RemoteFilesView(model: failedFixture.model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-stale-path-\(label).png"
                )
            )
            failedFixture.model.cancelAll()

            let largeTextFixture = try task037WorkspaceFixture(entries: entries)
            let largeInterfaceScale = 1.25
            try capture(
                view: RemoteFilesView(model: largeTextFixture.model)
                    .frame(
                        width: RemoteFilesWindowSizing.workspace.width
                            / largeInterfaceScale,
                        height: RemoteFilesWindowSizing.workspace.height
                            / largeInterfaceScale
                    )
                    .scaleEffect(largeInterfaceScale, anchor: .topLeading)
                    .frame(
                        width: RemoteFilesWindowSizing.workspace.width,
                        height: RemoteFilesWindowSizing.workspace.height,
                        alignment: .topLeading
                    ),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.workspace,
                to: outputDirectory.appendingPathComponent(
                    "task-037-larger-text-\(label).png"
                )
            )
            largeTextFixture.model.cancelAll()
        }
    }

    private func task037WorkspaceFixture(
        entries: [RemoteFileEntry]
    ) throws -> (
        model: RemoteFilesModel,
        service: Task037SnapshotService,
        presenter: Task037SnapshotPresenter
    ) {
        let catalog = RemoteServerCatalog()
        let server = try catalog.add(name: "Production builds", sshHost: "deploy@prod.example")
        _ = catalog.recordSuccessfulOpen(
            server,
            path: "/srv/releases/teams/platform/a-very-long-project-name/build-artifacts"
        )
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2026")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2025")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2024")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2023")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2022")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases/archive/2021")
        _ = catalog.recordSuccessfulOpen(server, path: "/srv/releases")
        let service = Task037SnapshotService(entries: entries)
        let presenter = Task037SnapshotPresenter()
        return (
            RemoteFilesModel(
                tunnels: [],
                service: service,
                presenter: presenter,
                serverCatalog: catalog
            ),
            service,
            presenter
        )
    }

    func testCaptureTask027Snapshots() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAYBAR_SNAPSHOT_DIR"] == nil,
            "Set RELAYBAR_SNAPSHOT_DIR to capture snapshots."
        )

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let label = appearanceName == .aqua ? "light" : "dark"
            let imageEntry = RemoteFileEntry(
                name: "launch-concept.png",
                path: "/srv/app/design/launch-concept.png",
                kind: .file,
                size: 84_120,
                modificationText: "Jul 30 09:42"
            )
            let readmeEntry = RemoteFileEntry(
                name: "README.md",
                path: "/srv/app/design/README.md",
                kind: .file,
                size: 4_862,
                modificationText: "Jul 30 10:18"
            )
            let architectureEntry = RemoteFileEntry(
                name: "preview-architecture.md",
                path: "/srv/app/design/preview-architecture.md",
                kind: .file,
                size: 12_540,
                modificationText: "Jul 29 18:05"
            )
            let alternateImageEntry = RemoteFileEntry(
                name: "navigation-study.jpg",
                path: "/srv/app/design/navigation-study.jpg",
                kind: .file,
                size: 118_300,
                modificationText: "Jul 29 16:32"
            )
            let notesEntry = RemoteFileEntry(
                name: "notes.txt",
                path: "/srv/app/design/notes.txt",
                kind: .file,
                size: 930,
                modificationText: "Jul 28 11:04"
            )
            let entries = [
                imageEntry,
                readmeEntry,
                architectureEntry,
                alternateImageEntry,
                notesEntry
            ]

            let fixtureRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "RelayBarTask027-\(UUID().uuidString)",
                    isDirectory: true
                )
            let imageDirectory = fixtureRoot.appendingPathComponent(
                "image-preview",
                isDirectory: true
            )
            let markdownDirectory = fixtureRoot.appendingPathComponent(
                "markdown-preview",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: imageDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: markdownDirectory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: fixtureRoot) }

            let imageURL = imageDirectory.appendingPathComponent(imageEntry.name)
            try task027ImageData().write(to: imageURL)
            let markdownURL = markdownDirectory.appendingPathComponent(readmeEntry.name)
            try Data(
                """
                # Remote Preview

                A focused workspace keeps nearby files in reach while the current
                document remains calm and readable.

                ## Release checklist

                - Reuse the active SSH connection
                - Preserve keyboard navigation
                - Keep temporary preview data private
                - Verify Aqua and Dark Aqua

                > The best interaction is the one that feels obvious after the
                > first click.

                ## Keyboard

                Use the left and right arrow keys to move between previewable files.
                Press Escape to return to the complete folder.
                """.utf8
            ).write(to: markdownURL)

            let service = Task027SnapshotService(
                entries: entries,
                previewURLs: [
                    imageEntry.id: imageURL,
                    readmeEntry.id: markdownURL
                ]
            )
            let tunnel = Tunnel(
                name: "Design server",
                localPort: 8_080,
                destinationHost: "localhost",
                destinationPort: 3_000,
                sshHost: "studio.local"
            )
            let model = RemoteFilesModel(
                tunnels: [tunnel],
                service: service,
                serverCatalog: RemoteServerCatalog()
            )
            model.remotePath = "/srv/app/design"
            model.openRemotePath()
            try await waitUntil {
                model.screen == .browser && !model.isLoading
            }

            model.preview(imageEntry)
            try await waitUntil {
                model.previewImage != nil && !model.isLoadingPreview
            }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.previewPreferred,
                to: outputDirectory.appendingPathComponent(
                    "task-027-image-sidebar-\(label).png"
                )
            )

            model.selectPreviewEntry(id: readmeEntry.id)
            try await waitUntil {
                model.previewMarkdown != nil && !model.isLoadingPreview
            }
            try capture(
                view: RemoteFilesView(model: model),
                appearance: appearanceName,
                size: RemoteFilesWindowSizing.previewPreferred,
                to: outputDirectory.appendingPathComponent(
                    "task-027-markdown-sidebar-\(label).png"
                )
            )
            try capture(
                view: RemoteFilesView(
                    model: model,
                    previewSidebarVisible: false
                ),
                appearance: appearanceName,
                size: NSSize(width: 780, height: 520),
                to: outputDirectory.appendingPathComponent(
                    "task-027-focused-\(label).png"
                )
            )
            model.cancelAll()
        }
    }

    private func task027ImageData() throws -> Data {
        let size = NSSize(width: 720, height: 480)
        let image = NSImage(size: size)
        image.lockFocus()
        let context = try XCTUnwrap(NSGraphicsContext.current?.cgContext)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = try XCTUnwrap(
            CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    CGColor(red: 0.08, green: 0.12, blue: 0.24, alpha: 1),
                    CGColor(red: 0.24, green: 0.20, blue: 0.48, alpha: 1)
                ] as CFArray,
                locations: [0, 1]
            )
        )
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size.height),
            end: CGPoint(x: size.width, y: 0),
            options: []
        )

        context.setFillColor(
            CGColor(red: 0.40, green: 0.82, blue: 0.96, alpha: 0.72)
        )
        context.fillEllipse(in: CGRect(x: 420, y: 170, width: 250, height: 250))

        context.addPath(
            CGPath(
                roundedRect: CGRect(x: 72, y: 72, width: 400, height: 310),
                cornerWidth: 28,
                cornerHeight: 28,
                transform: nil
            )
        )
        context.setFillColor(
            CGColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 0.93)
        )
        context.fillPath()

        context.addPath(
            CGPath(
                roundedRect: CGRect(x: 112, y: 280, width: 190, height: 22),
                cornerWidth: 11,
                cornerHeight: 11,
                transform: nil
            )
        )
        context.setFillColor(
            CGColor(red: 0.24, green: 0.36, blue: 0.94, alpha: 1)
        )
        context.fillPath()

        for index in 0..<3 {
            context.addPath(
                CGPath(
                    roundedRect: CGRect(
                        x: 112,
                        y: 222 - CGFloat(index * 50),
                        width: index == 2 ? 210 : 310,
                        height: 12
                    ),
                    cornerWidth: 6,
                    cornerHeight: 6,
                    transform: nil
                )
            )
            let brightness = 0.76 + CGFloat(index) * 0.04
            context.setFillColor(
                CGColor(
                    red: brightness,
                    green: brightness,
                    blue: brightness,
                    alpha: 1
                )
            )
            context.fillPath()
        }

        image.unlockFocus()
        let representation = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))
        )
        return try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
    }

    private func capture(
        view: some View,
        appearance: NSAppearance.Name,
        size: NSSize = NSSize(width: 380, height: 440),
        scrollOffsetY: CGFloat? = nil,
        assertHorizontalContainment: Bool = false,
        to url: URL
    ) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: appearance)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        // SwiftUI resolves its first layout pass on the run loop.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let scrollOffsetY {
            let scrollView = try XCTUnwrap(
                firstScrollableView(in: hosting),
                "Expected the captured view to contain a vertical scroll view."
            )
            let documentView = try XCTUnwrap(scrollView.documentView)
            let maximumOffset = max(
                0,
                documentView.bounds.height - scrollView.contentView.bounds.height
            )
            let offset = min(max(0, scrollOffsetY), maximumOffset)
            let targetY = documentView.isFlipped
                ? documentView.bounds.minY + offset
                : documentView.bounds.minY + maximumOffset - offset
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            let scrollDeadline = Date().addingTimeInterval(0.25)
            while Date() < scrollDeadline {
                RunLoop.current.run(
                    mode: .default,
                    before: Date().addingTimeInterval(0.05)
                )
            }
        }

        if assertHorizontalContainment {
            let scrollView = try XCTUnwrap(
                firstScrollView(in: hosting),
                "Expected the captured view to contain a scroll view."
            )
            let documentView = try XCTUnwrap(scrollView.documentView)
            XCTAssertFalse(scrollView.hasHorizontalScroller)
            XCTAssertEqual(
                scrollView.contentView.bounds.minX,
                0,
                accuracy: 0.5
            )
            XCTAssertLessThanOrEqual(
                documentView.bounds.width,
                scrollView.contentView.bounds.width + 1
            )
        }

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 2_000, "snapshot looks empty")
    }

    private func firstScrollableView(in view: NSView) -> NSScrollView? {
        if
            let scrollView = view as? NSScrollView,
            let documentView = scrollView.documentView,
            documentView.bounds.height > scrollView.contentView.bounds.height + 1
        {
            return scrollView
        }
        for subview in view.subviews {
            if let match = firstScrollableView(in: subview) {
                return match
            }
        }
        return nil
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let match = firstScrollView(in: subview) {
                return match
            }
        }
        return nil
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try XCTUnwrap(
            condition() ? true : nil,
            "Timed out waiting for snapshot fixture state."
        )
    }
}

@MainActor
private final class SnapshotUpdateService: UpdateServicing {
    let isAvailable = true
    var automaticallyChecksForUpdates = false
    var canCheckForUpdates = true
    var deferredInstallTunnelCount: Int?
    var stateDidChange: (@MainActor () -> Void)?
    private var completion: (@MainActor (UpdateCheckResult) -> Void)?

    func start() {}
    func checkForUpdates(
        completion: @escaping @MainActor (UpdateCheckResult) -> Void
    ) {
        self.completion = completion
    }
    func complete(with result: UpdateCheckResult) {
        completion?(result)
        completion = nil
    }
    func prepareForApplicationTermination() -> Bool { false }
}

@MainActor
private struct SnapshotPasteboardWriter: PasteboardWriting {
    func write(_ string: String) -> Bool { true }
}

@MainActor
private struct SnapshotAccessibilityAnnouncer: AccessibilityAnnouncing {
    func announce(_ message: String) {}
}

@MainActor
private final class Task037SnapshotPresenter: RemoteFilePresenting {
    var uploadFile: URL?

    func chooseDestination(for entry: RemoteFileEntry) -> URL? { nil }
    func chooseUploadFile() -> URL? { uploadFile }
    func confirmUploadReplacement(name: String) -> Bool { true }
    func revealInFinder(_ destination: URL) {}
}

private final class Task037SnapshotService: RemoteFileServing, @unchecked Sendable {
    let entries: [RemoteFileEntry]
    private let lock = NSLock()
    private var errors: [String: Error] = [:]
    private var isUploadSuspended = false
    var previewURL: URL?
    var uploadError: Error?

    init(entries: [RemoteFileEntry]) {
        self.entries = entries
    }

    func setError(_ error: Error, for path: String) {
        lock.lock()
        errors[path] = error
        lock.unlock()
    }

    func setUploadSuspended(_ suspended: Bool) {
        lock.lock()
        isUploadSuspended = suspended
        lock.unlock()
    }

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        let error = withLock { errors[path] }
        if let error { throw error }
        return entries
    }

    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        throw RemoteFileError.commandFailed("Download was not expected.")
    }

    func preparePreview(
        server: RemoteServer,
        entry: RemoteFileEntry
    ) async throws -> URL {
        guard let previewURL else {
            throw RemoteFileError.commandFailed("Preview fixture was not found.")
        }
        return previewURL
    }

    func upload(
        server: RemoteServer,
        localFile: URL,
        remoteDirectory: String,
        replaceExisting: Bool,
        phase: @escaping @Sendable (RemoteUploadPhase) -> Void
    ) async throws {
        phase(.staging)
        while uploadIsSuspended {
            try await Task.sleep(for: .milliseconds(20))
        }
        if let uploadError { throw uploadError }
        phase(.publishing)
    }

    private var uploadIsSuspended: Bool {
        withLock { isUploadSuspended }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class Task027SnapshotService: RemoteFileServing, @unchecked Sendable {
    let entries: [RemoteFileEntry]
    let previewURLs: [String: URL]

    init(entries: [RemoteFileEntry], previewURLs: [String: URL]) {
        self.entries = entries
        self.previewURLs = previewURLs
    }

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        entries
    }

    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        throw RemoteFileError.commandFailed("Download was not expected.")
    }

    func preparePreview(
        server: RemoteServer,
        entry: RemoteFileEntry
    ) async throws -> URL {
        guard let url = previewURLs[entry.id] else {
            throw RemoteFileError.commandFailed("Preview fixture was not found.")
        }
        return url
    }
}

private final class Task026SnapshotService: RemoteFileServing, @unchecked Sendable {
    private let lock = NSLock()
    private var listings: [String: [RemoteFileEntry]] = [:]
    private var suspendedPaths: Set<String> = []
    private var errors: [String: Error] = [:]

    func setListing(_ entries: [RemoteFileEntry], for path: String) {
        lock.lock()
        listings[path] = entries
        lock.unlock()
    }

    func setSuspended(_ suspended: Bool, for path: String) {
        lock.lock()
        if suspended {
            suspendedPaths.insert(path)
        } else {
            suspendedPaths.remove(path)
        }
        lock.unlock()
    }

    func setError(_ error: Error, for path: String) {
        lock.lock()
        errors[path] = error
        lock.unlock()
    }

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        while state(for: path).isSuspended {
            try await Task.sleep(for: .milliseconds(20))
        }
        let state = state(for: path)
        if let error = state.error {
            throw error
        }
        return state.entries
    }

    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        throw RemoteFileError.commandFailed("Download was not expected.")
    }

    func preparePreview(
        server: RemoteServer,
        entry: RemoteFileEntry
    ) async throws -> URL {
        throw RemoteFileError.commandFailed("Preview was not expected.")
    }

    private func state(
        for path: String
    ) -> (isSuspended: Bool, error: Error?, entries: [RemoteFileEntry]) {
        lock.lock()
        defer { lock.unlock() }
        return (
            suspendedPaths.contains(path),
            errors[path],
            listings[path] ?? []
        )
    }
}
