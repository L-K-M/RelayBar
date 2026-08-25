import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import RelayBarCore

/// Program entry point.
///
/// RelayBar is a menu-bar agent (`LSUIElement`), so it runs as an `.accessory`
/// app with no Dock icon. A plain `NSApplication` lifecycle rather than a
/// SwiftUI `App` scene is what keeps the status item addressable: `MenuBarExtra`
/// owns its `NSStatusItem` privately and exposes neither `autosaveName` nor
/// `isVisible`, so an app built on it cannot name, repair, or re-assert its own
/// icon once the system has persisted that icon as hidden.
@main
enum RelayBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = RelayBarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct StatusItemSummary: Equatable {
    enum State: Hashable {
        case stopped
        case active
        case issue
    }

    let activeCount: Int
    let failedCount: Int

    init(activeCount: Int, failedCount: Int) {
        self.activeCount = activeCount
        self.failedCount = failedCount
    }

    init<Phases: Sequence>(phases: Phases) where Phases.Element == TunnelPhase {
        var activeCount = 0
        var failedCount = 0
        for phase in phases {
            if phase.isLifecycleActive {
                activeCount += 1
            }
            if case .failed = phase {
                failedCount += 1
            }
        }
        self.init(activeCount: activeCount, failedCount: failedCount)
    }

    var state: State {
        if failedCount > 0 { return .issue }
        if activeCount > 0 { return .active }
        return .stopped
    }

    var accessibilityValue: String {
        switch state {
        case .stopped:
            return "All tunnels stopped"
        case .active:
            return activeDescription
        case .issue:
            if activeCount == 0 {
                return "\(failedDescription), no tunnels active"
            }
            return "\(failedDescription), \(activeDescription)"
        }
    }

    var toolTip: String {
        "RelayBar — \(accessibilityValue)"
    }

    func requiresImageReplacement(comparedTo previous: StatusItemSummary) -> Bool {
        state != previous.state
    }

    private var activeDescription: String {
        activeCount == 1 ? "1 tunnel active" : "\(activeCount) tunnels active"
    }

    private var failedDescription: String {
        failedCount == 1 ? "1 profile failed" : "\(failedCount) profiles failed"
    }
}

@MainActor
final class RelayBarAppDelegate:
    NSObject, NSApplicationDelegate, NSPopoverDelegate
{
    /// An explicit, stable autosave name. AppKit persists the item's slot and
    /// its visibility under `NSStatusItem Preferred Position <name>` and
    /// `NSStatusItem Visible <name>` in RelayBar's own defaults domain.
    /// `MenuBarExtra` left the name to AppKit, which assigns one by creation
    /// order — `Item-0` — so the persisted state was neither recognizable as
    /// RelayBar's nor reachable from RelayBar.
    private static let statusItemAutosaveName = "com.relaybarscion.RelayBarScion.status"

    private lazy var store = TunnelStore.shared
    private lazy var updates = UpdateModel(service: UpdateServiceFactory.shared)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusItemSummary = StatusItemSummary(
        activeCount: 0,
        failedCount: 0
    )
    private var popoverToggleGuard = PopoverToggleGuard()
    private var statusItemShowsActiveTunnels = false
    private var tunnelActivityObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before TunnelStore.shared reads its first key: the new bundle
        // identifier means a new, empty preferences domain.
        LegacyDefaultsMigration.run()
        installMainMenu()
        setUpStatusItem()
        observeTunnelActivity()
        UpdateServiceFactory.shared.start()
        if !configureDebugPreviewIfNeeded() {
            store.startProfilesMarkedForAutoStart()
        }
    }

    /// Re-launching the app — double-clicking it in Finder, or `open -a
    /// RelayBar` — re-asserts the icon and opens the menu. Without this, an
    /// agent app whose only surface is a hidden status item offers no way back
    /// in: relaunching an already-running `LSUIElement` app starts no second
    /// process and, unhandled, does nothing at all.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        presentPopover()
        return false
    }

    /// RelayBar keeps no custom restorable state, so opting in costs nothing
    /// and silences the macOS 14+ launch warning.
    func applicationSupportsSecureRestorableState(
        _ app: NSApplication
    ) -> Bool {
        true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if UpdateServiceFactory.shared.prepareForApplicationTermination() {
            // The updater takes over this quit; clear the flag so its own
            // post-install terminate is never mistaken for a user quit.
            RelayBarAppDelegate.userInitiatedQuitRequested = false
            return .terminateCancel
        }
        // Prompt only for quits the user asked for through RelayBar's own
        // controls (the ⌘Q menu item or the footer button). The updater's
        // post-install terminate re-enters this delegate — asking again
        // would double-prompt a decision the user already made — and
        // logout/shutdown quits must never be blocked by a modal. Both
        // arrive without the flag.
        guard
            RelayBarAppDelegate.userInitiatedQuitRequested,
            store.runningCount > 0
        else {
            return .terminateNow
        }
        // `runningCount` is the store's one definition of active — starting,
        // retrying, or running (isLifecycleActive) — so connect and backoff
        // phases are covered, not just settled tunnels.
        return presentQuitConfirmation()
    }

    /// True from the moment the user asks to quit through RelayBar's own
    /// controls until the confirmation (if any) completes, so termination
    /// can tell deliberate quits apart from updater, logout, and shutdown
    /// quits — which must never be prompted or blocked.
    private(set) static var userInitiatedQuitRequested = false

    static func requestUserQuit() {
        userInitiatedQuitRequested = true
        NSApplication.shared.terminate(nil)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        RelayBarAppDelegate.requestUserQuit()
    }

    /// Presenting a modal alert synchronously inside the terminate dispatch
    /// spins a nested run loop mid-termination, where a second quit event or
    /// a timer can re-enter this path. Apple's pattern for confirming during
    /// termination is to answer later: present on the next turn, then reply.
    private var quitConfirmationInFlight = false

    /// Starts the confirmation and returns the reply the caller owes
    /// AppKit. A duplicate terminate while the alert is already up is
    /// cancelled: the in-flight confirmation's single reply resolves the
    /// first request, and a second `.terminateLater` would wait forever for
    /// a reply that never comes.
    private func presentQuitConfirmation() -> NSApplication.TerminateReply {
        guard !quitConfirmationInFlight else { return .terminateCancel }
        quitConfirmationInFlight = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                // Documented as unreachable, which is exactly why it logs: if
                // delegate ownership ever changes, quitting without a prompt
                // needs to be explicable from the console.
                NSLog(
                    "RelayBar Scion: delegate released before the quit "
                        + "confirmation; terminating without prompting."
                )
                // Returning .terminateLater owes AppKit exactly one reply.
                // The delegate outlives every quit today — main() holds it
                // for the process lifetime — but a deallocated delegate
                // here would strand termination with no way to quit but
                // Force Quit, so answer rather than fall out silently.
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
                return
            }
            defer { quitConfirmationInFlight = false }
            // The tunnels that triggered the prompt may have stopped while
            // it was queued; confirm only against work still alive now.
            let activeCount = store.runningCount
            guard activeCount > 0 else {
                NSApplication.shared.reply(
                    toApplicationShouldTerminate: true
                )
                return
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = QuitConfirmation.messageText
            alert.informativeText = QuitConfirmation.informativeText(
                activeTunnelCount: activeCount
            )
            let stopButton = alert.addButton(
                withTitle: QuitConfirmation.stopButtonTitle(
                    activeTunnelCount: activeCount
                )
            )
            // The default action kills every live SSH process; say so in red.
            stopButton.hasDestructiveAction = true
            alert.addButton(withTitle: QuitConfirmation.cancelButtonTitle)
            let confirmed = alert.runModal() == .alertFirstButtonReturn
            RelayBarAppDelegate.userInitiatedQuitRequested = false
            NSApplication.shared.reply(
                toApplicationShouldTerminate: confirmed
            )
        }
        // The alert is answered on a later turn, so AppKit must be told to
        // wait for that reply rather than terminate now.
        return .terminateLater
    }

    // MARK: Status item

    private func setUpStatusItem() {
        StatusItemDefaults.removeMenuBarExtraState()
        StatusItemDefaults.repairImplausiblePreferredPosition(
            autosaveName: Self.statusItemAutosaveName,
            widestScreenWidth: NSScreen.screens
                .map { Double($0.frame.width) }
                .max() ?? 0
        )

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        // Name the item before asserting visibility. AppKit keys the restored
        // value off `autosaveName`, so naming it second would let a restored
        // `false` win over the assignment below.
        item.autosaveName = Self.statusItemAutosaveName
        item.isVisible = true

        statusItemSummary = currentStatusItemSummary
        if let button = item.button {
            button.image = Self.statusBarImage(
                state: statusItemSummary.state
            )
            // Image-only: the button must never lay out a title, whatever the
            // image turns out to be.
            button.imagePosition = .imageOnly
            button.setAccessibilityTitle("RelayBar")
            button.setAccessibilityValue(statusItemSummary.accessibilityValue)
            button.toolTip = statusItemSummary.toolTip
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
    }

    /// A fixed-size template glyph, as both reference menu-bar apps use. Two
    /// things matter beyond appearance. The item is image-only and roughly 18
    /// points wide rather than the ~100 the old `Label("RelayBar",
    /// systemImage:)` took once SwiftUI drew the title beside the icon, and
    /// width is what decides which items a crowded or notched menu bar drops.
    /// And a symbol lookup can return nil, which would leave the button with no
    /// image and nothing to click, so it falls back to a drawn glyph.
    static func statusBarImage(state: StatusItemSummary.State) -> NSImage {
        let symbolName: String
        switch state {
        case .stopped:
            symbolName = "arrow.left.arrow.right.circle"
        case .active:
            symbolName = "arrow.left.arrow.right.circle.fill"
        case .issue:
            symbolName = "exclamationmark.circle.fill"
        }
        if
            let symbol = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "RelayBar"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            )
        {
            symbol.isTemplate = true
            return symbol
        }
        return drawnStatusBarImage(state: state)
    }

    /// Drawn status glyphs echo their SF Symbols and remain template images so
    /// the system tints them for light and dark menu bars.
    private static func drawnStatusBarImage(state: StatusItemSummary.State) -> NSImage {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            let circle = NSBezierPath(
                ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15)
            )
            if state == .stopped {
                NSColor.black.setStroke()
                circle.lineWidth = 1.4
                circle.stroke()
            } else {
                NSColor.black.setFill()
                circle.fill()
            }

            if state == .issue {
                let context = NSGraphicsContext.current
                context?.saveGraphicsState()
                context?.compositingOperation = .destinationOut
                let stem = NSBezierPath()
                stem.move(to: NSPoint(x: 9, y: 6.8))
                stem.line(to: NSPoint(x: 9, y: 12.2))
                stem.lineWidth = 1.7
                stem.lineCapStyle = .round
                NSColor.black.setStroke()
                stem.stroke()

                let dot = NSBezierPath(
                    ovalIn: NSRect(x: 8.1, y: 4.1, width: 1.8, height: 1.8)
                )
                NSColor.black.setFill()
                dot.fill()
                context?.restoreGraphicsState()
                return true
            }

            let arrows = NSBezierPath()
            arrows.move(to: NSPoint(x: 12, y: 11))
            arrows.line(to: NSPoint(x: 6, y: 11))
            arrows.move(to: NSPoint(x: 8.5, y: 13))
            arrows.line(to: NSPoint(x: 6, y: 11))
            arrows.line(to: NSPoint(x: 8.5, y: 9))
            arrows.move(to: NSPoint(x: 6, y: 7))
            arrows.line(to: NSPoint(x: 12, y: 7))
            arrows.move(to: NSPoint(x: 9.5, y: 9))
            arrows.line(to: NSPoint(x: 12, y: 7))
            arrows.line(to: NSPoint(x: 9.5, y: 5))
            arrows.lineWidth = 1.4
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round

            // Knock the arrows out of the filled disc so they stay legible.
            let context = NSGraphicsContext.current
            let knocksOutArrows = state == .active
            if knocksOutArrows {
                context?.saveGraphicsState()
                context?.compositingOperation = .destinationOut
            }
            NSColor.black.setStroke()
            arrows.stroke()
            if knocksOutArrows {
                context?.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The icon distinguishes stopped, active, and failed states.
    /// `objectWillChange` fires before the store mutates, so the counts are read
    /// on the next main-actor turn.
    private func observeTunnelActivity() {
        tunnelActivityObserver = store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshStatusItemImage()
                }
            }
    }

    private func refreshStatusItemImage() {
        let summary = currentStatusItemSummary
        guard summary != statusItemSummary else { return }
        let previousSummary = statusItemSummary
        let stateChanged = summary.requiresImageReplacement(
            comparedTo: previousSummary
        )
        statusItemSummary = summary

        guard let button = statusItem?.button else { return }
        if stateChanged {
            button.image = Self.statusBarImage(state: summary.state)
        }
        button.setAccessibilityValue(summary.accessibilityValue)
        button.toolTip = summary.toolTip
        if stateChanged {
            NSAccessibility.post(element: button, notification: .valueChanged)
        }
    }

    private var currentStatusItemSummary: StatusItemSummary {
        StatusItemSummary(phases: store.phases.values)
    }

    /// Recreates the item if it is somehow gone and re-asserts visibility
    /// otherwise, so every route that opens the menu also repairs the icon.
    private func reassertStatusItem() {
        guard let statusItem else {
            setUpStatusItem()
            return
        }
        statusItem.isVisible = true
    }

    // MARK: Menu

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else if
            !PopoverToggleGuard.shouldSuppressToggle(
                eventType: NSApp.currentEvent?.type
            )
                // Short-circuit is load-bearing: shouldPresent() consumes
                // the recorded close, so only mouse-up toggles may call it;
                // other toggles must present without disarming the guard.
                || popoverToggleGuard.shouldPresent(
                    now: NSApp.currentEvent?.timestamp
                        ?? ProcessInfo.processInfo.systemUptime
                )
        {
            presentPopover()
        }
    }

    private func presentPopover() {
        reassertStatusItem()
        guard let button = statusItem?.button else { return }
        let popover = menuPopover()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The profile editor has text fields, so the popover has to take key
        // status rather than merely appear.
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    /// Built once and reused, so the root view keeps its navigation state
    /// between openings the way the `MenuBarExtra` window did.
    private func menuPopover() -> NSPopover {
        if let popover { return popover }
        let popover = NSPopover()
        popover.contentSize = NSSize(
            width: RelayBarPopoverLayout.width,
            height: RelayBarPopoverLayout.height
        )
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RelayBarRootView(updateModel: updates)
                .environmentObject(store)
        )
        self.popover = popover
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        guard
            PopoverToggleGuard.shouldRecordClose(
                eventType: NSApp.currentEvent?.type
            )
        else {
            return
        }
        // A mouse-down close only races the toggle when the mouse-down
        // landed on the icon itself; a dismissal click anywhere else
        // (desktop, another window) must not disarm the next deliberate
        // icon click. Unknown-event closes (app deactivation) skip the
        // hit-test and record, the safer default.
        if NSApp.currentEvent != nil, !isPointerOverStatusItem() { return }
        // Record in the gesture's own clock domain: NSEvent timestamps and
        // system uptime share the monotonic boot clock, so the toggle's
        // event timestamp measures the actual click hold time.
        popoverToggleGuard.recordClose(
            uptime: NSApp.currentEvent?.timestamp
                ?? ProcessInfo.processInfo.systemUptime
        )
    }

    private func isPointerOverStatusItem() -> Bool {
        guard let buttonWindow = statusItem?.button?.window else { return false }
        return buttonWindow.frame.contains(NSEvent.mouseLocation)
    }

    /// An agent app has no menu bar of its own, so without a main menu the
    /// standard editing key equivalents never reach the first responder and
    /// ⌘X/⌘C/⌘V/⌘A do nothing in the profile editor or the Remote Files window.
    /// The SwiftUI `App` scene used to supply this for free.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = appMenu.addItem(
            withTitle: "Quit RelayBar",
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(.separator())
        // `NSText` is where AppKit declares these four, so `#selector` can name
        // them. Undo and redo above have no declaration to point at — they only
        // ever travel the responder chain — so they stay string selectors.
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    #if DEBUG
    private var previewWindow: NSWindow?
    private var tunnelPreviewStore: TunnelStore?
    private var tunnelPreviewDefaultsSuite: String?
    private var remoteFilesPreviewPresenter: RemoteFilesPreviewPresenter?

    private func configureDebugPreviewIfNeeded() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-dark") {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        } else if arguments.contains("--preview-light") {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        if
            let livePreviewIndex = arguments.firstIndex(of: "--remote-files-live-preview"),
            arguments.indices.contains(livePreviewIndex + 1)
        {
            let sshHost = arguments[livePreviewIndex + 1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard SSHArgumentPolicy.isValidHostTarget(sshHost) else { return false }

            NSApplication.shared.setActivationPolicy(.regular)
            let tunnel = Tunnel(
                name: "",
                localPort: 1,
                destinationHost: "localhost",
                destinationPort: 1,
                sshHost: sshHost
            )
            let presenter = RemoteFilesPreviewPresenter()
            remoteFilesPreviewPresenter = presenter
            RemoteFilesWindowController.shared.show(
                tunnels: [tunnel],
                presenter: presenter,
                catalog: RemoteServerCatalog()
            )
            return true
        }
        if arguments.contains("--remote-files-preview") {
            NSApplication.shared.setActivationPolicy(.regular)
            let tunnels = [
                Tunnel(
                    name: "127.0.0.1:5902 Virtual Desktop",
                    localPort: 5_902,
                    destinationHost: "127.0.0.1",
                    destinationPort: 5_902,
                    sshHost: "spark-422e.local"
                ),
                Tunnel(
                    name: "Hermes Dashboard",
                    localPort: 9_119,
                    destinationHost: "127.0.0.1",
                    destinationPort: 9_119,
                    sshHost: "spark-422e.local"
                ),
                Tunnel(
                    name: "127.0.0.1:4321",
                    localPort: 4_321,
                    destinationHost: "127.0.0.1",
                    destinationPort: 4_321,
                    sshHost: "spark-422e.local"
                ),
                Tunnel(
                    name: "",
                    localPort: 3_000,
                    destinationHost: "127.0.0.1",
                    destinationPort: 3_000,
                    sshHost: "linxy97@spark-422e"
                )
            ]
            let presenter = RemoteFilesPreviewPresenter()
            remoteFilesPreviewPresenter = presenter
            RemoteFilesWindowController.shared.show(
                tunnels: tunnels,
                service: RemoteFilesPreviewService(),
                presenter: presenter,
                catalog: RemoteServerCatalog()
            )
            return true
        }
        guard arguments.contains("--preview-window") else { return false }
        NSApplication.shared.setActivationPolicy(.regular)

        let previewStore: TunnelStore
        if arguments.contains("--grouping-preview") {
            let suite = "RelayBar.GroupingPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let store = TunnelStore(defaults: defaults)
            let scenario: String
            if
                let index = arguments.firstIndex(of: "--grouping-preview"),
                arguments.indices.contains(index + 1),
                !arguments[index + 1].hasPrefix("--")
            {
                scenario = arguments[index + 1]
            } else {
                scenario = "mixed"
            }
            let fixtures: [(name: String, group: String?)]
            switch scenario {
            case "empty":
                fixtures = []
            case "all-untagged", "zero-tag":
                fixtures = [
                    ("Hermes Dashboard", nil),
                    ("Virtual Desktop", nil),
                    ("Scratch", nil)
                ]
            case "one-bucket":
                fixtures = [
                    ("Hermes Dashboard", "Work"),
                    ("Virtual Desktop", "Work"),
                    ("Preview Server", "Work")
                ]
            case "all-tagged":
                fixtures = [
                    ("Hermes Dashboard", "Work"),
                    ("Virtual Desktop", "Work"),
                    ("Photos", "Personal")
                ]
            case "long-tag":
                let maximumWidthGroup = "Group "
                    + String(repeating: "🌐", count: 26)
                fixtures = [
                    ("Quarterly Dashboard", maximumWidthGroup),
                    ("Research Preview", maximumWidthGroup)
                ]
            case "many-sections":
                fixtures = [
                    ("Build Monitor", "Engineering"),
                    ("CRM", "Client Work"),
                    ("Photos", "Personal"),
                    ("Research", "Research"),
                    ("Status", "Operations"),
                    ("Preview", "Design")
                ]
            default:
                fixtures = [
                    ("Hermes Dashboard", "Work"),
                    ("Virtual Desktop", "Work"),
                    ("Photos", "Personal"),
                    ("Scratch", nil)
                ]
            }

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
            tunnelPreviewStore = store
            tunnelPreviewDefaultsSuite = suite
            previewStore = store
        } else if arguments.contains("--flexible-forwarding-preview") {
            let suite = "RelayBar.FlexibleForwardingPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let store = TunnelStore(defaults: defaults)
            store.add(
                Tunnel(
                    name: "Development Web",
                    sshHost: "dev@example.com",
                    rules: [
                        .localTCP(
                            bindAddress: "localhost",
                            port: 3_000,
                            destinationHost: "localhost",
                            destinationPort: 3_000
                        )
                    ]
                )
            )
            store.add(
                Tunnel(
                    name: "Web, SOCKS & Preview",
                    sshHost: "bastion.example.com",
                    additionalArguments: ["-p", "2222"],
                    rules: [
                        .localTCP(
                            bindAddress: "localhost",
                            port: 8_080,
                            destinationHost: "web.internal",
                            destinationPort: 80
                        ),
                        ForwardingRule(
                            kind: .localDynamic,
                            listen: .tcp(bindAddress: "localhost", port: 1_080)
                        ),
                        ForwardingRule(
                            kind: .remote,
                            listen: .tcp(bindAddress: "localhost", port: 0),
                            destination: .tcp(host: "localhost", port: 4_321)
                        )
                    ]
                )
            )
            store.add(
                Tunnel(
                    name: "Restricted Reverse SOCKS",
                    sshHost: "gateway.example.com",
                    rules: [
                        ForwardingRule(
                            kind: .remoteDynamic,
                            listen: .tcp(bindAddress: "0.0.0.0", port: 1_081)
                        )
                    ],
                    reverseSOCKSPolicy: .allow([
                        "api.example.com:443",
                        "*.internal:8443"
                    ])
                )
            )
            tunnelPreviewStore = store
            tunnelPreviewDefaultsSuite = suite
            previewStore = store
        } else {
            previewStore = TunnelStore.shared
        }

        let rootView = RelayBarRootView(
            updateModel: UpdateModel(service: UnavailableUpdateService())
        )
            .environmentObject(previewStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RelayBar Preview"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        previewWindow = window
        return true
    }
    #else
    private func configureDebugPreviewIfNeeded() -> Bool { false }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        RemoteFilesWindowController.shared.close()
        #if DEBUG
        remoteFilesPreviewPresenter?.cleanup()
        if let tunnelPreviewDefaultsSuite {
            UserDefaults.standard.removePersistentDomain(
                forName: tunnelPreviewDefaultsSuite
            )
        }
        #endif
        TunnelStore.shared.stopAll()
    }
}

/// Guards the status-item toggle against the dismissal the same click
/// already caused. The popover's behavior is `.transient`, so clicking the
/// menu-bar icon while the popover is open closes it on mouse-down — the
/// click lands outside the popover window — and the button action only runs
/// on mouse-up. Reading `isShown` in the action therefore always sees
/// "closed" and would immediately re-present the popover, making the icon
/// unable to dismiss it. The guard treats a toggle that lands inside a short
/// window after a close caused by an outside mouse-down as the tail of that
/// same click and swallows it once. Timing uses the monotonic system uptime
/// clock, not wall-clock time, so an NTP step cannot distort the window.
struct PopoverToggleGuard {
    /// The mouse-down close and mouse-up action of one click arrive well
    /// inside this window, and deliberate clicks elsewhere no longer arm the
    /// guard, so slow click-and-hold releases cost nothing to cover.
    static let suppressionWindow: TimeInterval = 0.6

    /// Only a close caused by a left mouse-down delivered outside the
    /// popover can be the front half of the click whose mouse-up runs the
    /// toggle action (the status button fires on left mouse-up only, so a
    /// right-click close can never race it). Escape, in-popover, and
    /// programmatic `performClose` closes (which arrive as key or mouse-up
    /// events) never race it, so they must not disarm a deliberate following
    /// click. An unknown event context — a close driven by app deactivation
    /// — records, the safer default for never re-opening over a real icon
    /// click. The delegate additionally hit-tests the mouse location against
    /// the status item, so dismissal clicks elsewhere do not arm the guard.
    static func shouldRecordClose(eventType: NSEvent.EventType?) -> Bool {
        guard let eventType else { return true }
        return eventType == .leftMouseDown
    }

    /// Only a toggle fired by a mouse-up can be the tail of the click that
    /// closed the popover. Keyboard, accessibility, and programmatic toggles
    /// always present, so the guard can never swallow the re-launch re-open
    /// escape hatch or an assistive activation.
    static func shouldSuppressToggle(eventType: NSEvent.EventType?) -> Bool {
        eventType == .leftMouseUp
    }

    private var lastCloseUptime: TimeInterval?

    mutating func recordClose(
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        lastCloseUptime = uptime
    }

    /// Returns `false` exactly once when the toggle lands within the
    /// suppression window of the recorded close, treating it as the click
    /// that already dismissed the popover. A close recorded by an intentional
    /// toggle-close is consumed the same way, so at worst one rapid re-click
    /// is ignored and the next one opens the menu.
    mutating func shouldPresent(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard let lastCloseUptime else { return true }
        if now - lastCloseUptime < Self.suppressionWindow {
            self.lastCloseUptime = nil
            return false
        }
        return true
    }
}

/// The user-facing copy of the active-tunnel quit confirmation, kept pure
/// so the pluralization stays testable away from a modal alert.
enum QuitConfirmation {
    static let messageText = "Quit RelayBar?"
    static let cancelButtonTitle = "Cancel"

    static func informativeText(activeTunnelCount: Int) -> String {
        activeTunnelCount == 1
            ? "1 tunnel is running. Quitting stops it."
            : "\(activeTunnelCount) tunnels are running. Quitting stops them."
    }

    static func stopButtonTitle(activeTunnelCount: Int) -> String {
        activeTunnelCount == 1 ? "Stop Tunnel and Quit" : "Stop Tunnels and Quit"
    }
}

/// This fork carries its own bundle identifier, which gives it a preferences
/// domain of its own and leaves every saved profile behind in the domain the
/// upstream identifier owned. This copies the user's data across once, on the
/// first launch that finds the new domain without it.
///
/// It copies and never moves. The app this fork came from may still be
/// installed and in use, and emptying its preferences out from under it would
/// be a second surprise on top of the rename.
enum LegacyDefaultsMigration {
    /// The bundle identifier this fork was built from.
    static let legacyDomainName = "com.lx2026.RelayBar"

    /// Keys holding work the user created. Runtime state, window state, and
    /// the status item's saved slot are deliberately absent: they describe the
    /// old identity's placement and cost nothing to rebuild.
    static let migratedKeys = [
        "savedTunnels.v2",
        "savedTunnels.v1",
        "remoteFiles.savedServers.v1",
        "remoteFiles.recentServers.v1",
        "remoteFiles.lastPaths.v1"
    ]

    static let completionKey = "migratedLegacyRelayBarDefaults"

    /// Returns the keys actually copied, which is empty on every launch after
    /// the first — including the first launch of a fresh install, where there
    /// is nothing to carry over.
    @discardableResult
    static func run(
        into defaults: UserDefaults = .standard,
        // Spelled with the type name because a default argument is compiled
        // as its own thunk rather than in the body's scope; qualifying it is
        // the reading that is unambiguously valid.
        from legacy: UserDefaults? = UserDefaults(
            suiteName: LegacyDefaultsMigration.legacyDomainName
        )
    ) -> [String] {
        guard !defaults.bool(forKey: completionKey) else { return [] }
        // A nil suite means the domain could not be opened at all, which is
        // not the same as finding it empty. Leave the flag unset so the next
        // launch looks again rather than recording a migration that never
        // read anything.
        guard let legacy else { return [] }
        // Marked before copying rather than after: a crash midway through
        // should not re-run against a domain the user has since edited here.
        defaults.set(true, forKey: completionKey)

        var copied: [String] = []
        for key in migratedKeys {
            // A value already under this identity wins. The user has used this
            // build; the old domain is only a seed for an empty one.
            guard
                defaults.object(forKey: key) == nil,
                let value = legacy.object(forKey: key)
            else {
                continue
            }
            defaults.set(value, forKey: key)
            copied.append(key)
        }

        if !copied.isEmpty {
            NSLog(
                // %ld, not %d: `count` is a 64-bit Int on every platform this
                // ships to.
                "RelayBar Scion carried %ld saved keys over from %@.",
                copied.count,
                legacyDomainName
            )
        }
        return copied
    }
}

/// AppKit autosaves a status item's slot and visibility into the owning app's
/// own defaults domain, and restores both on every later launch. That is the
/// mechanism behind an icon that appears once and never again: nothing in the
/// app re-asserts the item, so a single persisted `false` — or a slot beyond
/// every attached screen — outlives the process, the rebuild, and the reinstall.
/// These helpers keep that state honest at launch.
enum StatusItemDefaults {
    /// AppKit's creation-order name for an item that never set `autosaveName`,
    /// which is what `MenuBarExtra` left RelayBar using.
    static let menuBarExtraAutosaveName = "Item-0"

    private static let preferredPositionPrefix = "NSStatusItem Preferred Position "
    /// macOS 26 renamed the visibility key to `VisibleCC`; both spellings are
    /// cleared so neither vintage can strand the item.
    private static let visibilityPrefixes = [
        "NSStatusItem Visible ",
        "NSStatusItem VisibleCC "
    ]
    /// How far past the widest screen a saved slot may sit before it is treated
    /// as junk rather than as an intentional position.
    private static let implausiblePositionSlack: Double = 512

    static func preferredPositionKey(autosaveName: String) -> String {
        preferredPositionPrefix + autosaveName
    }

    static func visibilityKeys(autosaveName: String) -> [String] {
        visibilityPrefixes.map { $0 + autosaveName }
    }

    /// Drops the state the old `MenuBarExtra` item left behind. Nothing reads
    /// those keys now that the item is explicitly named, and a stale
    /// `NSStatusItem Visible Item-0 = 0` is precisely the value that makes an
    /// icon unrecoverable, so it is cleared rather than left to rot.
    static func removeMenuBarExtraState(in defaults: UserDefaults = .standard) {
        let keys = [preferredPositionKey(autosaveName: menuBarExtraAutosaveName)]
            + visibilityKeys(autosaveName: menuBarExtraAutosaveName)
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    /// Clears a saved slot that no screen can display. AppKit restores the
    /// value verbatim, so an item parked past the right edge — or at a
    /// nonsensical zero or negative offset — stays undrawable until the key
    /// goes away. Removing it lets the next launch place the item normally; a
    /// plausible position is left alone so the user's arrangement survives.
    static func repairImplausiblePreferredPosition(
        autosaveName: String,
        widestScreenWidth: Double,
        defaults: UserDefaults = .standard
    ) {
        let key = preferredPositionKey(autosaveName: autosaveName)
        guard let saved = defaults.object(forKey: key) as? Double else { return }
        guard
            saved <= 0 || saved > widestScreenWidth + implausiblePositionSlack
        else {
            return
        }
        defaults.removeObject(forKey: key)
    }
}

#if DEBUG
private final class RemoteFilesPreviewService: RemoteFileServing, @unchecked Sendable {
    private let stateLock = NSLock()
    private var listRequestCounts: [String: Int] = [:]

    func list(server: RemoteServer, path: String) async throws -> [RemoteFileEntry] {
        try await Task.sleep(for: .milliseconds(250))

        if path.hasSuffix("/empty") {
            return []
        }
        if path.hasSuffix("/reports") {
            return [
                entry("weekly-summary.md", path: path, size: 8_420),
                entry("metrics.csv", path: path, size: 42_700)
            ]
        }
        if path.hasSuffix("/unstable") {
            if requestCount(for: path) == 2 {
                throw RemoteFileError.commandFailed("The connection was lost.")
            }
            return [
                entry("recovered-report.md", path: path, size: 7_680)
            ]
        }

        switch path {
        case "/workspace":
            throw RemoteFileError.commandFailed("The remote path wasn’t found.")
        case "/permission-denied":
            throw RemoteFileError.commandFailed(
                "Permission was denied for this server or path."
            )
        case "/host-key-failure":
            throw RemoteFileError.commandFailed(
                "SSH could not verify this server’s host key."
            )
        case "/connection-lost":
            throw RemoteFileError.commandFailed("The connection was lost.")
        default:
            break
        }

        return [
            entry("empty", path: path, kind: .directory),
            entry("reports", path: path, kind: .directory),
            entry("screenshots", path: path, kind: .directory),
            entry("unstable", path: path, kind: .directory),
            entry("dashboard.png", path: path, size: 1_258_291),
            entry(
                "quarterly-analysis-with-an-intentionally-long-filename-for-layout-verification.csv",
                path: path,
                size: 842_700
            ),
            entry("README.md", path: path, size: 4_096),
            entry("permission-denied.bin", path: path, size: 4_000_000),
            entry("results.zip", path: path, size: 3_565_158),
            entry("slow-download.bin", path: path, size: 50_000_000)
        ]
    }

    func download(
        server: RemoteServer,
        entry: RemoteFileEntry,
        to destination: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let total = entry.size ?? 2_000_000
        let stepCount = entry.name == "slow-download.bin" ? 100 : 20
        for step in 1...stepCount {
            try Task.checkCancellation()
            progress(total * Int64(step) / Int64(stepCount))
            try await Task.sleep(for: .milliseconds(100))
            if entry.name == "permission-denied.bin", step == 5 {
                throw RemoteFileError.commandFailed(
                    "Permission was denied for this server or path."
                )
            }
        }
        if entry.isDirectory {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } else {
            try Data("RelayBar preview download".utf8).write(to: destination)
        }
    }

    private func requestCount(for path: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        let count = (listRequestCounts[path] ?? 0) + 1
        listRequestCounts[path] = count
        return count
    }

    func preparePreview(server: RemoteServer, entry: RemoteFileEntry) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelayBarPreviewReview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = directory.appendingPathComponent(entry.name)
        if entry.isPreviewableMarkdown {
            try Data(markdownPreview.utf8).write(to: destination)
        } else {
            try makePreviewImage(at: destination)
        }
        return destination
    }

    private func entry(
        _ name: String,
        path: String,
        kind: RemoteFileEntry.Kind = .file,
        size: Int64? = nil
    ) -> RemoteFileEntry {
        RemoteFileEntry(
            name: name,
            path: RemotePath.joining(path, name),
            kind: kind,
            size: size,
            modificationText: "Jul 24 00:20"
        )
    }

    private func makePreviewImage(at url: URL) throws {
        let width = 1_200
        let height = 720
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw RemoteFileError.unsupportedImage
        }

        context.setFillColor(CGColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 70, y: 70, width: 1_060, height: 580))
        context.setStrokeColor(CGColor(red: 0.18, green: 0.50, blue: 0.98, alpha: 1))
        context.setLineWidth(8)
        context.move(to: CGPoint(x: 120, y: 210))
        context.addCurve(
            to: CGPoint(x: 1_080, y: 500),
            control1: CGPoint(x: 390, y: 570),
            control2: CGPoint(x: 720, y: 160)
        )
        context.strokePath()

        for index in 0..<8 {
            let barHeight = CGFloat(110 + ((index * 47) % 260))
            context.setFillColor(CGColor(red: 0.18, green: 0.50, blue: 0.98, alpha: 0.55))
            context.fill(
                CGRect(
                    x: CGFloat(155 + index * 115),
                    y: 120,
                    width: 58,
                    height: barHeight
                )
            )
        }

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw RemoteFileError.unsupportedImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RemoteFileError.unsupportedImage
        }
    }

    private var markdownPreview: String {
        """
        ---
        status: ready
        environment: production
        reviewers:
          - Product
          - Security
        summary: |
          Safe remote reading.
          No vault indexing.
        ---

        # RelayBar remote report

        This is a **read-only** Markdown preview from the selected server.
        Text remains selectable, [safe web links](https://example.com) open only when clicked,
        and a [remote setup guide](Guides/Setup.md#Install) stays inside the vault boundary. ^preview-summary

        > [!warning] Safe by default
        > Remote HTML is never executed, and images are not loaded automatically.

        > [!faq]- Folded in the source
        > RelayBar keeps remote content visible in its continuous reading view.
        >
        > > [!todo]+ Nested check
        > > Fold markers and nesting stay clear without adding disclosure controls.

        ## Delivery status

        | Capability | State |
        | --- | --- |
        | Exact-path browsing | Ready |
        | Image preview | Ready |
        | Markdown rendering | Ready |
        | Table-safe alias | [[Operations\\|Runbook]] |

        - [x] GitHub-flavored tables
        - [x] Task lists and strikethrough
        - [?] Custom Obsidian task status
        - [ ] Remote editing

        The compatibility layer preserves ==important notes==, shows [[Operations|wiki links]]
        without fetching them, and lists footnotes at the end.[^safety]
        The #production/relaybar tag stays visible without indexing the remote vault.

        Inline math renders natively: $E = mc^2$.

        $$
        \\int_0^1 x^2\\,dx = \\frac{1}{3}
        $$

        ```swift
        let service = RemoteFilesService()
        await service.open(path: "/srv/app/output")
        let lifecycle = ["download", "decode", "render", "review"].map { stage in "\\(stage): cancellation-safe and independently bounded" }.joined(separator: " → ")
        ```

        ```mermaid
        graph LR
          Remote --> Preview
        ```

        ![[private-diagram.png]]

        ![A remote chart that is intentionally not fetched|640x360][review-chart]

        [review-chart]: https://example.com/chart.png

        %% This reading-mode comment is intentionally hidden. %%

        [^safety]: Linked remote content is never fetched implicitly.
          Two-space continuation lines stay with the footnote.

        <script
          data-mode="literal">
        alert("This is displayed as text, never executed.")
        </script>

        [<style>HTML-looking link label</style>](https://example.com)
        """
    }
}

@MainActor
private final class RemoteFilesPreviewPresenter: RemoteFilePresenting {
    private let rootURL: URL

    init() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RelayBarRemoteFilesUIReview-\(UUID().uuidString)",
                isDirectory: true
            )
        try? FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func chooseDestination(for entry: RemoteFileEntry) -> URL? {
        rootURL.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
    }

    func revealInFinder(_ destination: URL) {
        // The review fixture stays isolated from Finder and external applications.
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
#endif
