import SwiftUI

/// One reused formatter. `ByteCountFormatter.string(fromByteCount:countStyle:)`
/// builds a formatter per call, and these run per row inside a render pass.
/// `.formatted(.byteCount(style: .file))` is not a substitute: it renders SI
/// `kB` rather than `KB` and rounds 999 bytes up to `1 kB`.
///
/// Confined to the main actor because `ByteCountFormatter` is not thread-safe
/// and every caller is a SwiftUI view body.
@MainActor
enum RemoteByteCount {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func string(_ byteCount: Int64) -> String {
        formatter.string(fromByteCount: byteCount)
    }
}

enum RemoteSidebarFocus: Hashable {
    case previewEntry(String)
    case location(UUID)
    case showAllRecentFolders
    case host(UUID)
    case showAllHostPaths(UUID)
}

enum RemoteSidebarFocusNavigator {
    static func adjacent(
        to current: RemoteSidebarFocus?,
        moving direction: MoveCommandDirection,
        within items: [RemoteSidebarFocus]
    ) -> RemoteSidebarFocus? {
        guard !items.isEmpty else { return nil }
        guard direction == .up || direction == .down else { return current }
        guard let current, let index = items.firstIndex(of: current) else {
            return direction == .up ? items.last : items.first
        }
        let offset = direction == .up ? -1 : 1
        return items[min(max(index + offset, 0), items.count - 1)]
    }
}

struct RemoteFilesView: View {
    @ObservedObject var model: RemoteFilesModel
    @FocusState private var focusedSidebarItem: RemoteSidebarFocus?
    @State private var isAddingPath = false
    @State private var isConfirmingServerRemoval = false
    @State private var pendingServerRemovalID: UUID?
    @State private var isPreviewSidebarVisible = true
    @State private var expandedHostIDs: Set<UUID> = []
    @State private var showsAllRecentFolders = false
    @State private var showsAllHostPaths: Set<UUID> = []
    @State private var isConfirmingRecentClear = false
    private let initialFocusedSidebarItem: RemoteSidebarFocus?

    init(
        model: RemoteFilesModel,
        previewSidebarVisible: Bool = true,
        expandedHostIDs: Set<UUID> = [],
        initialFocusedSidebarItem: RemoteSidebarFocus? = nil
    ) {
        self.model = model
        _isPreviewSidebarVisible = State(initialValue: previewSidebarVisible)
        _expandedHostIDs = State(initialValue: expandedHostIDs)
        self.initialFocusedSidebarItem = initialFocusedSidebarItem
    }

    var body: some View {
        Group {
            if isPreviewSidebarVisible {
                HSplitView {
                    workspaceSidebar
                        .frame(minWidth: 210, idealWidth: 250, maxWidth: 360)
                    workspaceDetail
                        .frame(minWidth: 430)
                        .layoutPriority(1)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                focusedSidebarItem = nil
                            }
                        )
                }
            } else {
                workspaceDetail
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            RemoteSidebarKeyboardMonitor(
                onActivate: activateFocusedSidebarItem,
                isEnabled: isPreviewSidebarVisible
                    && effectiveFocusedSidebarItem != nil
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            if focusedSidebarItem == nil {
                focusedSidebarItem = initialFocusedSidebarItem
            }
        }
        .sheet(isPresented: $isAddingPath) {
            AddRemotePathView(model: model)
        }
        .confirmationDialog(
            "Clear all recent remote paths?",
            isPresented: $isConfirmingRecentClear
        ) {
            Button("Clear Recent Locations", role: .destructive) {
                model.clearRecentLocations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved hosts, forwarding profiles, and SSH config will not change.")
        }
        .confirmationDialog(
            "Remove this saved host?",
            isPresented: $isConfirmingServerRemoval
        ) {
            Button("Remove Saved Host", role: .destructive) {
                if let pendingServerRemovalID {
                    model.removeSavedServer(id: pendingServerRemovalID)
                }
                pendingServerRemovalID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingServerRemovalID = nil
            }
        } message: {
            Text("Its recent paths are removed. Forwarding profiles and SSH config will not change.")
        }
    }

    @ViewBuilder private var workspaceDetail: some View {
        switch model.screen {
        case .welcome:
            workspaceWelcome
        case .browser:
            browser
        case .preview:
            workspacePreview
        }
    }

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Locations")
                    .font(.headline)
                Spacer()
                Button {
                    isAddingPath = true
                } label: {
                    Label("Add Path…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.canActivateLocation)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.screen == .preview, !model.previewableEntries.isEmpty {
                        sidebarSection("IN THIS FOLDER") {
                            ForEach(model.previewableEntries) { entry in
                                Button {
                                    model.selectPreviewEntry(id: entry.id)
                                } label: {
                                    PreviewSidebarRow(
                                        entry: entry,
                                        isSelected: model.previewEntry?.id == entry.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.canActivateLocation)
                                .focused(
                                    $focusedSidebarItem,
                                    equals: .previewEntry(entry.id)
                                )
                            }
                        }
                    }

                    if !model.recentLocations.isEmpty {
                        sidebarSection("RECENT FOLDERS") {
                            ForEach(globallyVisibleRecentLocations) { location in
                                RemoteLocationRow(
                                    location: location,
                                    isActiveRoot: model.screen == .browser
                                        && model.activeLocationID == location.id,
                                    isWorkspaceRoot: model.activeLocationID == location.id,
                                    isKeyboardFocused: effectiveFocusedSidebarItem
                                        == .location(location.id),
                                    onActivate: { model.activate(location) },
                                    onRemove: { model.removeRecentLocation(id: location.id) }
                                )
                                .disabled(!model.canActivateLocation)
                                .focused(
                                    $focusedSidebarItem,
                                    equals: .location(location.id)
                                )
                            }
                            if model.recentLocations.count > model.recentFolderLocations.count {
                                Button(showsAllRecentFolders ? "Show Less" : "Show All Recent Folders…") {
                                    showsAllRecentFolders.toggle()
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 9)
                                .padding(.top, 3)
                                .focused(
                                    $focusedSidebarItem,
                                    equals: .showAllRecentFolders
                                )
                            }
                        } menu: {
                            Button("Clear Recent Locations…", role: .destructive) {
                                isConfirmingRecentClear = true
                            }
                        }
                    }

                    let recentHosts = model.servers(from: .recent)
                    if !recentHosts.isEmpty {
                        sidebarSection("RECENT HOSTS") {
                            ForEach(recentHosts) { server in
                                recentHost(server)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .onMoveCommand(perform: moveSidebarFocus)

            Divider()
            Text("Recent paths stay on this Mac. RelayBar connects only after you open one.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .background(.ultraThinMaterial)
        .accessibilityLabel("Remote locations")
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 9)
            content()
        }
    }

    private func sidebarSection<Content: View, MenuContent: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                Menu {
                    menu()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .accessibilityLabel("Recent folders actions")
            }
            .padding(.horizontal, 9)
            content()
        }
    }

    @ViewBuilder private func recentHost(_ server: RemoteServer) -> some View {
        let visibleKeys = Set(globallyVisibleRecentLocations.map(\.key))
        let allPaths = model.recentLocations.filter {
            $0.server.connectionIdentity == server.connectionIdentity
                && !visibleKeys.contains($0.key)
        }
        let canExpand = !allPaths.isEmpty
        let isExpanded = canExpand && expandedHostIDs.contains(server.id)
        let nestedPaths = showsAllHostPaths.contains(server.id)
            ? allPaths
            : model.nestedLocations(
                for: server,
                excluding: globallyVisibleRecentLocations
            )

        Button {
            if canExpand {
                if isExpanded {
                    expandedHostIDs.remove(server.id)
                } else {
                    expandedHostIDs.insert(server.id)
                }
            } else {
                model.selectedServerID = server.id
                isAddingPath = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(
                    systemName: canExpand
                        ? (isExpanded ? "chevron.down" : "chevron.right")
                        : "plus"
                )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(model.recentLocationCount(for: server)) recent "
                        + (model.recentLocationCount(for: server) == 1 ? "path" : "paths"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canActivateLocation)
        .focused($focusedSidebarItem, equals: .host(server.id))
        .contextMenu {
            Button("Add Path…") {
                model.selectedServerID = server.id
                isAddingPath = true
            }
            .disabled(!model.canActivateLocation)
            if model.isSavedServer(id: server.id) {
                Divider()
                Button("Remove Saved Host…", role: .destructive) {
                    pendingServerRemovalID = server.id
                    isConfirmingServerRemoval = true
                }
                .disabled(!model.canActivateLocation)
            }
        }
        .accessibilityLabel(
            "\(server.displayName), \(model.recentLocationCount(for: server)) recent "
                + (model.recentLocationCount(for: server) == 1 ? "path" : "paths")
        )
        .accessibilityHint(
            canExpand ? "Show remote paths" : "Add a path for this host"
        )

        if isExpanded {
            ForEach(nestedPaths) { location in
                RemoteLocationRow(
                    location: location,
                    isActiveRoot: model.screen == .browser
                        && model.activeLocationID == location.id,
                    isWorkspaceRoot: model.activeLocationID == location.id,
                    isKeyboardFocused: effectiveFocusedSidebarItem == .location(location.id),
                    isNested: true,
                    onActivate: { model.activate(location) },
                    onRemove: { model.removeRecentLocation(id: location.id) }
                )
                .disabled(!model.canActivateLocation)
                .focused(
                    $focusedSidebarItem,
                    equals: .location(location.id)
                )
            }
            if allPaths.count > model.nestedLocations(
                for: server,
                excluding: globallyVisibleRecentLocations
            ).count {
                Button(showsAllHostPaths.contains(server.id) ? "Show Less" : "Show All Paths…") {
                    if showsAllHostPaths.contains(server.id) {
                        showsAllHostPaths.remove(server.id)
                    } else {
                        showsAllHostPaths.insert(server.id)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 40)
                .padding(.top, 2)
                .focused(
                    $focusedSidebarItem,
                    equals: .showAllHostPaths(server.id)
                )
            }
        }
    }

    private var sidebarFocusItems: [RemoteSidebarFocus] {
        var items: [RemoteSidebarFocus] = []
        if model.screen == .preview {
            items += model.previewableEntries.map {
                .previewEntry($0.id)
            }
        }

        items += globallyVisibleRecentLocations.map { .location($0.id) }
        if model.recentLocations.count > model.recentFolderLocations.count {
            items.append(.showAllRecentFolders)
        }

        for server in model.servers(from: .recent) {
            items.append(.host(server.id))
            guard expandedHostIDs.contains(server.id) else { continue }
            let visibleKeys = Set(globallyVisibleRecentLocations.map(\.key))
            let allPaths = model.recentLocations.filter {
                $0.server.connectionIdentity == server.connectionIdentity
                    && !visibleKeys.contains($0.key)
            }
            let visiblePaths = showsAllHostPaths.contains(server.id)
                ? allPaths
                : model.nestedLocations(
                    for: server,
                    excluding: globallyVisibleRecentLocations
                )
            items += visiblePaths.map { .location($0.id) }
            if allPaths.count > model.nestedLocations(
                for: server,
                excluding: globallyVisibleRecentLocations
            ).count {
                items.append(.showAllHostPaths(server.id))
            }
        }
        return items
    }

    private var globallyVisibleRecentLocations: [RemoteLocation] {
        showsAllRecentFolders ? model.recentLocations : model.recentFolderLocations
    }

    private var effectiveFocusedSidebarItem: RemoteSidebarFocus? {
        focusedSidebarItem ?? initialFocusedSidebarItem
    }

    @discardableResult
    private func activateFocusedSidebarItem() -> Bool {
        guard let focusedSidebarItem = effectiveFocusedSidebarItem else { return false }
        switch focusedSidebarItem {
        case .previewEntry(let id):
            guard model.canActivateLocation else { return false }
            model.selectPreviewEntry(id: id)
        case .location(let id):
            guard
                model.canActivateLocation,
                let location = model.recentLocations.first(where: { $0.id == id })
            else { return false }
            model.activate(location)
        case .showAllRecentFolders:
            showsAllRecentFolders.toggle()
        case .host(let id):
            guard
                model.canActivateLocation,
                let server = model.servers(from: .recent).first(where: { $0.id == id })
            else { return false }
            let hasNestedPaths = model.recentLocations.contains {
                $0.server.connectionIdentity == server.connectionIdentity
                    && !Set(globallyVisibleRecentLocations.map(\.key)).contains($0.key)
            }
            if hasNestedPaths {
                if expandedHostIDs.contains(id) {
                    expandedHostIDs.remove(id)
                } else {
                    expandedHostIDs.insert(id)
                }
            } else {
                model.selectedServerID = id
                isAddingPath = true
            }
        case .showAllHostPaths(let id):
            if showsAllHostPaths.contains(id) {
                showsAllHostPaths.remove(id)
            } else {
                showsAllHostPaths.insert(id)
            }
        }
        return true
    }

    private func moveSidebarFocus(_ direction: MoveCommandDirection) {
        if case .host(let serverID) = focusedSidebarItem {
            if direction == .right {
                expandedHostIDs.insert(serverID)
                return
            }
            if direction == .left {
                expandedHostIDs.remove(serverID)
                return
            }
        }
        focusedSidebarItem = RemoteSidebarFocusNavigator.adjacent(
            to: focusedSidebarItem,
            moving: direction,
            within: sidebarFocusItems
        )
    }

    private var workspaceWelcome: some View {
        VStack(spacing: 0) {
            HStack {
                sidebarToggle
                Spacer()
                Text(model.isLoading ? model.presentedPath : "Choose a remote location")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {}
                    .disabled(true)
                Button("Upload…") {}
                    .disabled(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            Divider()
            if let errorMessage = model.errorMessage {
                LoadErrorStrip(
                    message: errorMessage,
                    onRetry: model.retryLastLoad,
                    onDismiss: model.dismissLoadError,
                    showsRemoveFromRecents: model.failedLocationID != nil,
                    onRemoveFromRecents: model.removeFailedLocation
                )
                Divider()
            }
            if model.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Opening remote folder…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Open a remote folder")
                        .font(.title3.weight(.semibold))
                    Text("Choose a recent folder or a path under a recent host. "
                        + "RelayBar won’t connect until you open a location.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 390)
                    Button("Add Path…") {
                        isAddingPath = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canActivateLocation)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            }
        }
    }

    private var workspacePreview: some View {
        VStack(spacing: 0) {
            previewToolbar
            Divider()
            previewDetail
        }
        .background(
            RemotePreviewKeyboardMonitor(
                onMovePrevious: { model.movePreviewSelection(by: -1) },
                onMoveNext: { model.movePreviewSelection(by: 1) },
                isEnabled: model.screen == .preview,
                isSidebarFocused: isPreviewSidebarVisible
                    && focusedSidebarItem != nil
            )
            .frame(width: 0, height: 0)
        )
        .onExitCommand {
            model.closePreview()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedSidebarItem = nil
            }
        )
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isPreviewSidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("s", modifiers: [.control, .command])
        .help(isPreviewSidebarVisible ? "Hide location sidebar" : "Show location sidebar")
        .accessibilityLabel(
            isPreviewSidebarVisible ? "Hide location sidebar" : "Show location sidebar"
        )
    }

    private var browser: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider()

            if let upload = model.upload {
                UploadStrip(model: model, upload: upload)
                Divider()
            }

            if let transfer = model.transfer {
                TransferStrip(model: model, transfer: transfer)
                Divider()
            }

            if let errorMessage = model.errorMessage {
                LoadErrorStrip(
                    message: errorMessage,
                    onRetry: model.retryLastLoad,
                    onDismiss: model.dismissLoadError,
                    showsRemoveFromRecents: model.failedLocationID != nil,
                    onRemoveFromRecents: model.removeFailedLocation
                )
                Divider()
            }

            if model.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Opening folder…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Empty folder")
                    Text("This folder is empty")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
        }
        .background(
            RemoteFilesKeyboardMonitor(
                onPreview: {
                    if let entry = model.selectedEntry, entry.isPreviewable {
                        model.preview(entry)
                        return true
                    }
                    return false
                },
                onActivate: {
                    guard let entry = model.selectedEntry else { return false }
                    model.activate(entry)
                    return true
                },
                isEnabled: model.screen == .browser,
                isSidebarFocused: isPreviewSidebarVisible
                    && focusedSidebarItem != nil
            )
            .frame(width: 0, height: 0)
        )
        .onExitCommand {
            if model.canGoBack {
                model.goBack()
            }
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            sidebarToggle

            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!model.canGoBack)
            .help(model.backHelp)

            Spacer()

            Text(model.presentedPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.presentedPath)
                .accessibilityLabel("Current path \(model.presentedPath)")

            Spacer()

            Button {
                model.refresh()
            } label: {
                if model.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refresh")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.canActivateLocation)

            Button {
                model.beginUpload()
            } label: {
                Label("Upload…", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canUpload)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private var fileList: some View {
        List(selection: $model.selectedEntryID) {
            ForEach(model.entries) { entry in
                RemoteFileRow(
                    entry: entry,
                    isSelected: model.selectedEntryID == entry.id,
                    onSelect: { model.select(entry) },
                    onActivate: { model.activate(entry) },
                    onPreview: { model.preview(entry) },
                    onDownload: { model.download(entry) }
                )
                .tag(entry.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .listRowSeparatorTint(Color.primary.opacity(0.08))
            }
        }
        .listStyle(.plain)
        .disabled(!model.canActivateEntry)
    }

    private var previewToolbar: some View {
        HStack(spacing: 10) {
            sidebarToggle

            Button {
                model.closePreview()
            } label: {
                Label("All Files", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back to folder")
            .disabled(!model.canGoBack)

            Divider()
                .frame(height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.previewEntry?.name ?? "Preview")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let entry = model.previewEntry {
                    Text(previewDescription(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            Button {
                if let entry = model.previewEntry {
                    model.download(entry)
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .disabled(
                model.transfer?.phase == .active
                    || model.transfer?.phase == .cancelling
            )
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private var previewDetail: some View {
        VStack(spacing: 0) {
            if let transfer = model.transfer {
                TransferStrip(model: model, transfer: transfer)
                Divider()
            }

            if model.isLoadingPreview {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading preview…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                errorState(message: errorMessage, retry: model.retryPreview)
            } else if let image = model.previewImage {
                GeometryReader { geometry in
                    let maximumWidth = max(0, geometry.size.width - 64)
                    let maximumHeight = max(0, geometry.size.height - 64)
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)

                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: min(image.size.width, maximumWidth),
                                height: min(image.size.height, maximumHeight)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                            .padding(32)
                            .accessibilityLabel(
                                "Image preview of "
                                    + "\(model.previewEntry?.name ?? "remote file")"
                            )
                    }
                }
            } else if let markdown = model.previewMarkdown {
                SafeRemoteMarkdownView(document: markdown)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func previewDescription(for entry: RemoteFileEntry) -> String {
        let kind = entry.isPreviewableImage ? "Image" : "Markdown"
        guard let size = entry.size else { return kind }
        return "\(kind) · \(RemoteByteCount.string(size))"
    }

    private func errorState(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct AddRemotePathView: View {
    @ObservedObject var model: RemoteFilesModel

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingHost = false
    @State private var isOpening = false
    @FocusState private var isPathFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Remote Path")
                    .font(.title3.weight(.semibold))
                Text("Choose an SSH host and enter an exact absolute path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Host")
                    .font(.caption.weight(.medium))
                HStack(spacing: 8) {
                    if model.servers.isEmpty {
                        Text("No SSH hosts available")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("Host", selection: $model.selectedServerID) {
                            ForEach(RemoteServer.Source.pickerOrder, id: \.self) { source in
                                let servers = model.servers(from: source)
                                if !servers.isEmpty {
                                    Section(source.pickerSectionTitle) {
                                        ForEach(servers) { server in
                                            Text(server.displayName)
                                                .tag(Optional(server.id))
                                        }
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(!model.canActivateLocation)
                    }
                    Button("Add Host…") {
                        isAddingHost = true
                    }
                    .disabled(!model.canActivateLocation)
                }
                Text("Recents, saved hosts, forwarding profiles, and SSH config")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Remote path")
                    .font(.caption.weight(.medium))
                TextField("/srv/app/output", text: $model.remotePath)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPathFocused)
                    .onSubmit(open)
                if let message = model.pathValidationMessage, !model.remotePath.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Enter an absolute path beginning with /")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isOpening, let errorMessage = model.errorMessage {
                ErrorMessage(message: errorMessage)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isOpening && model.isLoading)
                Button(action: open) {
                    if isOpening && model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Open")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canOpen)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isPathFocused = true
        }
        .onChange(of: model.successfulOpenSequence) { _ in
            if isOpening {
                dismiss()
            }
        }
        .interactiveDismissDisabled(isOpening && model.isLoading)
        .sheet(isPresented: $isAddingHost) {
            AddRemoteServerView { name, sshHost in
                try model.addServer(name: name, sshHost: sshHost)
            }
        }
    }

    private func open() {
        guard model.canOpen else { return }
        isOpening = true
        model.openRemotePath()
    }
}

private struct RemoteLocationRow: View {
    let location: RemoteLocation
    let isActiveRoot: Bool
    let isWorkspaceRoot: Bool
    let isKeyboardFocused: Bool
    var isNested = false
    let onActivate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 8) {
                Image(systemName: isNested ? "arrow.turn.down.right" : "folder.fill")
                    .font(.system(size: isNested ? 10 : 14))
                    .foregroundStyle(isActiveRoot ? Color.white : Color.accentColor)
                    .frame(width: 19)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isNested ? location.path : location.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !isNested {
                        Text("\(location.server.displayName) · \(location.path)")
                            .font(.caption2)
                            .foregroundStyle(isActiveRoot ? Color.white.opacity(0.78) : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if isWorkspaceRoot && !isActiveRoot {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Workspace root")
                }
            }
            .padding(.horizontal, isNested ? 20 : 8)
            .frame(minHeight: isNested ? 29 : 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActiveRoot ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isKeyboardFocused
                            ? (isActiveRoot ? Color.white : Color.accentColor)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open", action: onActivate)
            Button("Remove from Recents", role: .destructive, action: onRemove)
        }
        .accessibilityLabel(
            "\(location.displayName), \(location.server.displayName), \(location.path)"
                + (isWorkspaceRoot ? ", workspace root" : "")
        )
        .accessibilityHint("Open this remote folder")
        .accessibilityAddTraits(isActiveRoot ? .isSelected : [])
    }
}

private struct PreviewSidebarRow: View {
    let entry: RemoteFileEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: entry.isPreviewableImage ? "photo" : "doc.richtext")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .frame(minHeight: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.20), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Select to preview this file")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var metadata: String {
        guard let size = entry.size else { return entry.modificationText }
        return "\(entry.modificationText) · \(RemoteByteCount.string(size))"
    }

    private var accessibilityLabel: String {
        let kind = entry.isPreviewableImage ? "image" : "Markdown document"
        return "\(entry.name), \(kind), \(metadata)"
    }
}

private struct AddRemoteServerView: View {
    let onAdd: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sshHost = ""
    @State private var errorMessage: String?
    @FocusState private var isHostFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add SSH Host")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name · Optional")
                    .font(.caption.weight(.medium))
                TextField("Development server", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SSH host")
                    .font(.caption.weight(.medium))
                TextField("user@server", text: $sshHost)
                    .textFieldStyle(.roundedBorder)
                    .focused($isHostFocused)
                    .onSubmit(add)
                Text("RelayBar uses your existing OpenSSH config, keys, and agent.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Host", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isHostFocused = true
        }
    }

    private func add() {
        do {
            try onAdd(name, sshHost)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RemoteFileRow: View {
    let entry: RemoteFileEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onPreview: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            Text(entry.name)
                .font(.callout.weight(entry.isDirectory ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 20)

            Text(entry.modificationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .trailing)

            Text(sizeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            if isSelected {
                Button {
                    onDownload()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help(entry.isDirectory ? "Download folder" : "Download file")
                .accessibilityLabel(entry.isDirectory ? "Download folder" : "Download file")
                .frame(width: 26)
            } else {
                Color.clear.frame(width: 26, height: 1)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 43)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if entry.isDirectory {
                Button("Open", action: onActivate)
            } else if entry.isPreviewable {
                Button("Preview", action: onPreview)
            }
            Button(entry.isDirectory ? "Download Folder…" : "Download…", action: onDownload)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(
            named: Text(entry.isDirectory ? "Open" : (entry.isPreviewable ? "Preview" : "Download")),
            onActivate
        )
        .accessibilityAction(named: Text(entry.isDirectory ? "Download Folder" : "Download"), onDownload)
    }

    private var iconName: String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isPreviewableImage { return "photo" }
        if entry.isPreviewableMarkdown { return "doc.richtext" }
        if entry.kind == .symbolicLink { return "link" }
        return "doc"
    }

    private var iconColor: Color {
        entry.isDirectory ? Color.accentColor : Color.secondary
    }

    private var sizeText: String {
        guard let size = entry.size else { return "—" }
        return RemoteByteCount.string(size)
    }

    private var accessibilityLabel: String {
        let type: String
        switch entry.kind {
        case .directory: type = "folder"
        case .file:
            if entry.isPreviewableImage {
                type = "image"
            } else if entry.isPreviewableMarkdown {
                type = "Markdown document"
            } else {
                type = "file"
            }
        case .symbolicLink: type = "symbolic link"
        }
        return "\(entry.name), \(type), modified \(entry.modificationText), \(sizeText)"
    }
}

private struct TransferStrip: View {
    @ObservedObject var model: RemoteFilesModel
    let transfer: RemoteFilesModel.TransferPresentation

    var body: some View {
        HStack(spacing: 11) {
            statusIcon
                .accessibilityLabel(statusAccessibilityLabel)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if transfer.phase == .active || transfer.phase == .cancelling {
                    if let fraction = transfer.fraction {
                        ProgressView(value: fraction)
                        .accessibilityLabel(title)
                        .accessibilityValue(progressText)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(title)
                            .accessibilityValue(progressText)
                    }
                } else if let message = transfer.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(transfer.phase == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if transfer.phase == .active {
                Text(progressText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    model.cancelTransfer()
                }
            } else if transfer.phase == .cancelling {
                Text(progressText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Canceling…") {}
                    .disabled(true)
            } else if transfer.phase == .completed {
                Button("Reveal in Finder") {
                    model.revealTransfer()
                }
                Button {
                    model.dismissTransfer()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss transfer")
            } else {
                Button("Try Again") {
                    model.retryTransfer()
                }
                Button("Dismiss") {
                    model.dismissTransfer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.06))
    }

    @ViewBuilder private var statusIcon: some View {
        switch transfer.phase {
        case .active:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
        case .cancelling:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch transfer.phase {
        case .active:
            return "Downloading \(transfer.entry.name)"
        case .cancelling:
            return "Canceling \(transfer.entry.name)"
        case .completed:
            return "Downloaded \(transfer.entry.name)"
        case .failed:
            return "Couldn’t download \(transfer.entry.name)"
        case .cancelled:
            return "Canceled \(transfer.entry.name)"
        }
    }

    private var statusAccessibilityLabel: String {
        switch transfer.phase {
        case .active:
            return "Download in progress"
        case .cancelling:
            return "Canceling download"
        case .completed:
            return "Download complete"
        case .failed:
            return "Download failed"
        case .cancelled:
            return "Download canceled"
        }
    }

    private var progressText: String {
        let completed = RemoteByteCount.string(transfer.completedBytes)
        guard let total = transfer.totalBytes else { return completed }
        return "\(completed) of \(RemoteByteCount.string(total))"
    }
}

private struct UploadStrip: View {
    @ObservedObject var model: RemoteFilesModel
    let upload: RemoteFilesModel.UploadPresentation

    var body: some View {
        HStack(spacing: 11) {
            statusIcon
                .accessibilityLabel(statusAccessibilityLabel)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if upload.phase == .active || upload.phase == .cancelling {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(title)
                        .accessibilityValue(upload.message ?? "In progress")
                } else if let message = upload.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(upload.phase == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if upload.phase == .active {
                Text(upload.message ?? "Staging safely…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancelUpload() }
            } else if upload.phase == .cancelling {
                Button("Canceling…") {}
                    .disabled(true)
            } else if upload.phase == .failed || upload.phase == .cancelled {
                Button("Try Again") { model.retryUpload() }
                Button("Dismiss") { model.dismissUpload() }
            } else {
                Button("Dismiss") { model.dismissUpload() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.06))
    }

    @ViewBuilder private var statusIcon: some View {
        switch upload.phase {
        case .active:
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(Color.accentColor)
        case .cancelling:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        let name = upload.localFile.lastPathComponent
        switch upload.phase {
        case .active: return "Uploading \(name)"
        case .cancelling: return "Canceling \(name)"
        case .completed: return "Uploaded \(name)"
        case .failed: return "Couldn’t upload \(name)"
        case .cancelled: return "Canceled \(name)"
        }
    }

    private var statusAccessibilityLabel: String {
        switch upload.phase {
        case .active: return "Upload in progress"
        case .cancelling: return "Canceling upload"
        case .completed: return "Upload complete"
        case .failed: return "Upload failed"
        case .cancelled: return "Upload canceled"
        }
    }
}

private struct LoadErrorStrip: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let showsRemoveFromRecents: Bool
    let onRemoveFromRecents: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Load error")

            Text(message)
                .font(.caption)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button("Try Again", action: onRetry)
            if showsRemoveFromRecents {
                Button("Remove from Recents", role: .destructive) {
                    onRemoveFromRecents()
                }
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.red.opacity(0.06))
    }
}

private struct ErrorMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum RemoteFilesKeyboardShortcut {
    static func isUnmodified(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function]) == []
    }

    static func isCommandDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.command, .numericPad, .function]) == []
            && flags.contains(.command)
    }
}

private struct RemoteSidebarKeyboardMonitor: NSViewRepresentable {
    let onActivate: () -> Bool
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivate: onActivate, isEnabled: isEnabled)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onActivate = onActivate
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onActivate: () -> Bool
        var isEnabled: Bool
        private var monitor: Any?

        init(onActivate: @escaping () -> Bool, isEnabled: Bool) {
            self.onActivate = onActivate
            self.isEnabled = isEnabled
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let mainThreadEvent = MainThreadNSEvent(value: event)
                let result = MainActor.assumeIsolated { () -> MainThreadNSEvent? in
                    guard let self else { return mainThreadEvent }
                    guard
                        self.isEnabled,
                        event.window === self.view?.window,
                        event.keyCode == 36 || event.keyCode == 76,
                        RemoteFilesKeyboardShortcut.isUnmodified(event.modifierFlags)
                    else { return mainThreadEvent }
                    return self.onActivate() ? nil : mainThreadEvent
                }
                return result?.value
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct RemoteFilesKeyboardMonitor: NSViewRepresentable {
    let onPreview: () -> Bool
    let onActivate: () -> Bool
    let isEnabled: Bool
    let isSidebarFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPreview: onPreview,
            onActivate: onActivate,
            isEnabled: isEnabled,
            isSidebarFocused: isSidebarFocused
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onPreview = onPreview
        context.coordinator.onActivate = onActivate
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isSidebarFocused = isSidebarFocused
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onPreview: () -> Bool
        var onActivate: () -> Bool
        var isEnabled: Bool
        var isSidebarFocused: Bool
        private var monitor: Any?

        init(
            onPreview: @escaping () -> Bool,
            onActivate: @escaping () -> Bool,
            isEnabled: Bool,
            isSidebarFocused: Bool
        ) {
            self.onPreview = onPreview
            self.onActivate = onActivate
            self.isEnabled = isEnabled
            self.isSidebarFocused = isSidebarFocused
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // AppKit invokes local event monitors on the installing thread. RelayBar
                // installs this monitor from the main actor, but the imported callback
                // lacks that annotation.
                let mainThreadEvent = MainThreadNSEvent(value: event)
                let result = MainActor.assumeIsolated { () -> MainThreadNSEvent? in
                    guard let self else { return mainThreadEvent }
                    return self.handle(mainThreadEvent.value)
                        .map(MainThreadNSEvent.init(value:))
                }
                return result?.value
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                isEnabled,
                !isSidebarFocused,
                event.window === view?.window,
                isFileListResponder(event.window?.firstResponder),
                RemoteFilesKeyboardShortcut.isUnmodified(event.modifierFlags)
            else {
                if
                    isEnabled,
                    event.window === view?.window,
                    isFileListResponder(event.window?.firstResponder),
                    event.keyCode == 125,
                    RemoteFilesKeyboardShortcut.isCommandDown(event.modifierFlags)
                {
                    return onActivate() ? nil : event
                }
                return event
            }

            switch event.keyCode {
            case 36, 76:
                return onActivate() ? nil : event
            case 49:
                return onPreview() ? nil : event
            default:
                return event
            }
        }

        private func isFileListResponder(_ responder: NSResponder?) -> Bool {
            guard let view = responder as? NSView else { return false }
            var currentView: NSView? = view
            while let candidate = currentView {
                if candidate is NSTableView || candidate is NSOutlineView {
                    return true
                }
                currentView = candidate.superview
            }
            return false
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct RemotePreviewKeyboardMonitor: NSViewRepresentable {
    let onMovePrevious: () -> Bool
    let onMoveNext: () -> Bool
    let isEnabled: Bool
    let isSidebarFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMovePrevious: onMovePrevious,
            onMoveNext: onMoveNext,
            isEnabled: isEnabled,
            isSidebarFocused: isSidebarFocused
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onMovePrevious = onMovePrevious
        context.coordinator.onMoveNext = onMoveNext
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isSidebarFocused = isSidebarFocused
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var onMovePrevious: () -> Bool
        var onMoveNext: () -> Bool
        var isEnabled: Bool
        var isSidebarFocused: Bool
        private var monitor: Any?

        init(
            onMovePrevious: @escaping () -> Bool,
            onMoveNext: @escaping () -> Bool,
            isEnabled: Bool,
            isSidebarFocused: Bool
        ) {
            self.onMovePrevious = onMovePrevious
            self.onMoveNext = onMoveNext
            self.isEnabled = isEnabled
            self.isSidebarFocused = isSidebarFocused
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let mainThreadEvent = MainThreadNSEvent(value: event)
                let result = MainActor.assumeIsolated { () -> MainThreadNSEvent? in
                    guard let self else { return mainThreadEvent }
                    return self.handle(mainThreadEvent.value)
                        .map(MainThreadNSEvent.init(value:))
                }
                return result?.value
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window = view?.window else {
                return event
            }
            guard
                isEnabled,
                !isSidebarFocused,
                event.window === window || NSApplication.shared.keyWindow === window,
                !hasActiveDocumentTextResponder(in: window),
                RemoteFilesKeyboardShortcut.isUnmodified(event.modifierFlags)
            else {
                return event
            }

            switch event.keyCode {
            case 123:
                return onMovePrevious() ? nil : event
            case 124:
                return onMoveNext() ? nil : event
            default:
                return event
            }
        }

        private func hasActiveDocumentTextResponder(in window: NSWindow) -> Bool {
            guard let textView = window.firstResponder as? NSTextView else {
                return false
            }
            return !textView.isFieldEditor
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct MainThreadNSEvent: @unchecked Sendable {
    let value: NSEvent
}
