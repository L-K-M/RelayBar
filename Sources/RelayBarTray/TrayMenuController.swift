import Foundation
import RelayBarCore
import CAppIndicator

/// Renders supervisor snapshots as a flat AppIndicator menu: one toggle per
/// profile, then Reload Profiles and Quit. GTK work must stay on the GLib
/// main thread, so `render` is always reached through an idle source.
final class TrayMenuController: @unchecked Sendable {
    private let supervisor: TunnelSupervisor
    private let profileStore: ProfileStore
    private var indicator: UnsafeMutableRawPointer?
    private var shell: UnsafeMutableRawPointer?

    /// Boxes stay registered between rebuilds; destroying a GTK item does
    /// not release its user_data pointer, so the controller owns them until
    /// the next wholesale rebuild drops the whole generation at once.
    private var liveBoxes: [ObjectIdentifier: ActionBox] = [:]

    static let iconFallbackName = "applications-internet"
    private static let maximumLabelCharacterCount = 64

    init(supervisor: TunnelSupervisor, profileStore: ProfileStore) {
        self.supervisor = supervisor
        self.profileStore = profileStore

        relaybar_gtk_init()
        guard let indicator = relaybar_indicator_new("relaybar-tray", Self.iconFallbackName) else {
            FileHandle.standardError.write(
                Data("relaybar-tray: could not create the status indicator\n".utf8)
            )
            return
        }
        self.indicator = indicator
        relaybar_indicator_set_title(indicator, "RelayBar")
        relaybar_indicator_set_active(indicator)

        let shell = relaybar_menu_new()
        self.shell = shell
        if let shell {
            relaybar_widget_show_all(shell)
            relaybar_indicator_set_menu(indicator, shell)
        }

        render(supervisor.snapshot())
        supervisor.onStateChange = { [weak self] in
            let snapshot = self?.supervisor.snapshot() ?? []
            self?.scheduleRender(snapshot)
        }
    }

    // MARK: - Rendering

    /// Rebuilds the whole menu on every state change. Profile counts are
    /// small, and wholesale rebuilds sidestep DBusMenu partial-update quirks.
    func render(_ entries: [SupervisedTunnel]) {
        guard let shell else { return }

        // Destroyed items can no longer fire; their boxes may be reclaimed.
        liveBoxes.removeAll()
        relaybar_clear_menu(shell)
        if entries.isEmpty {
            let hint = relaybar_plain_item_new("No profiles loaded — add ~/.config/relaybar/tunnels.json")
            relaybar_item_set_sensitive(hint, 0)
            relaybar_menu_append(shell, hint)
        }
        for entry in entries {
            appendToggle(for: entry, shell: shell)
        }
        appendSeparator(to: shell)
        appendAction("Reload Profiles", to: shell) { context in context.reload() }
        appendAction("Quit", to: shell) { context in context.quit() }
        relaybar_widget_show_all(shell)

        if let indicator {
            relaybar_indicator_set_menu(indicator, shell)
        }
    }

    private func label(for phase: TunnelPhase, name: String) -> String {
        let stateSuffix: String
        switch phase {
        case .stopped: stateSuffix = ""
        case .starting: stateSuffix = " — starting…"
        case .running: stateSuffix = ""
        case .retrying(let attempt, let maxAttempts, _, _):
            stateSuffix = " — retry \(attempt)/\(maxAttempts)"
        case .failed:
            stateSuffix = " — failed (select to retry)"
        }
        return "\(name)\(stateSuffix)"
    }

    private func appendToggle(for entry: SupervisedTunnel, shell: UnsafeMutableRawPointer?) {
        var name = entry.profile.displayName
        if name.count > Self.maximumLabelCharacterCount {
            name = String(name.prefix(Self.maximumLabelCharacterCount - 1)) + "…"
        }
        let isChecked = isLifecycleActive(entry.phase)

        let box = register(ActionBox(action: .toggle(profileID: entry.profile.id), controller: self))
        let item = relaybar_check_item_new(label(for: entry.phase, name: name), isChecked ? 1 : 0)
        relaybar_connect_activate(item, { _, userData in
            guard let userData else { return }
            Unmanaged<ActionBox>.fromOpaque(userData).takeUnretainedValue().perform()
        }, Unmanaged.passUnretained(box).toOpaque())
        relaybar_menu_append(shell, item)
    }

    private func appendSeparator(to shell: UnsafeMutableRawPointer?) {
        relaybar_menu_append(shell, relaybar_separator_new())
    }

    private func appendAction(
        _ title: String,
        to shell: UnsafeMutableRawPointer?,
        perform action: @escaping (ActionContext) -> Void
    ) {
        let box = register(ActionBox(action: .custom(title, action), controller: self))
        let item = relaybar_plain_item_new(title)
        relaybar_connect_activate(item, { _, userData in
            guard let userData else { return }
            Unmanaged<ActionBox>.fromOpaque(userData).takeUnretainedValue().perform()
        }, Unmanaged.passUnretained(box).toOpaque())
        relaybar_menu_append(shell, item)
    }

    private func register(_ box: ActionBox) -> ActionBox {
        liveBoxes[ObjectIdentifier(box)] = box
        return box
    }

    private func scheduleRender(_ snapshot: [SupervisedTunnel]) {
        let box = Unmanaged.passRetained(RenderBox(snapshot: snapshot, controller: self)).toOpaque()
        relaybar_idle_add({ userData in
            guard let userData else { return 0 }
            // Consumes the passRetained from scheduleRender: the idle source
            // has no destroy notify, so this is the box's only release.
            let box = Unmanaged<RenderBox>.fromOpaque(userData).takeRetainedValue()
            box.controller.render(box.snapshot)
            return 0 // G_SOURCE_REMOVE
        }, box)
    }

    // MARK: - Actions

    fileprivate func handle(_ action: MenuAction) {
        switch action {
        case .toggle(let profileID):
            toggle(profileID: profileID)
        case .custom(_, let perform):
            perform(ActionContext(reload: handleReload, quit: handleQuit))
        }
    }

    private func toggle(profileID id: UUID) {
        let isActive = supervisor.snapshot().contains {
            $0.profile.id == id && isLifecycleActive($0.phase)
        }
        if isActive {
            supervisor.stop(profileID: id)
        } else {
            supervisor.start(profileID: id)
        }
    }

    private func handleReload() {
        supervisor.reloadProfiles(profileStore.load())
    }

    private func handleQuit() {
        Shutdown.shared.request()
    }

    private func isLifecycleActive(_ phase: TunnelPhase) -> Bool {
        phase.isLifecycleActive
    }
}

// MARK: - Callback plumbing

/// Context handed to generic menu actions.
struct ActionContext {
    let reload: () -> Void
    let quit: () -> Void
}

enum MenuAction {
    case toggle(profileID: UUID)
    case custom(String, (ActionContext) -> Void)
}

/// Boxes a menu action and its owning controller for a C callback pointer.
private final class ActionBox: @unchecked Sendable {
    let action: MenuAction
    weak var controller: TrayMenuController?

    init(action: MenuAction, controller: TrayMenuController) {
        self.action = action
        self.controller = controller
    }

    func perform() {
        controller?.handle(action)
    }
}

/// Boxes a pending render for the GLib idle source.
private final class RenderBox: @unchecked Sendable {
    let snapshot: [SupervisedTunnel]
    let controller: TrayMenuController

    init(snapshot: [SupervisedTunnel], controller: TrayMenuController) {
        self.snapshot = snapshot
        self.controller = controller
    }
}
