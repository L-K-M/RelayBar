import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

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
    private static let statusItemAutosaveName = "com.lx2026.RelayBar.status"

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
        UpdateServiceFactory.shared.prepareForApplicationTermination()
            ? .terminateCancel
            : .terminateNow
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
        } else if popoverToggleGuard.shouldPresent() {
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
        popoverToggleGuard.recordClose()
    }

    /// An agent app has no menu bar of its own, so without a main menu the
    /// standard editing key equivalents never reach the first responder and
    /// ⌘X/⌘C/⌘V/⌘A do nothing in the profile editor or the Remote Files window.
    /// The SwiftUI `App` scene used to supply this for free.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit RelayBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
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
/// window after any close as the tail of that same click and swallows it
/// once.
struct PopoverToggleGuard {
    /// The mouse-down close and mouse-up action of one click arrive well
    /// inside this window; two deliberate clicks do not.
    static let suppressionWindow: TimeInterval = 0.35

    private var lastClose: Date?

    mutating func recordClose(now: Date = Date()) {
        lastClose = now
    }

    /// Returns `false` exactly once when the toggle lands within the
    /// suppression window of the recorded close, treating it as the click
    /// that already dismissed the popover. A close recorded by an intentional
    /// toggle-close is consumed the same way, so at worst one rapid re-click
    /// is ignored and the next one opens the menu.
    mutating func shouldPresent(now: Date = Date()) -> Bool {
        guard let lastClose else { return true }
        if now.timeIntervalSince(lastClose) < Self.suppressionWindow {
            self.lastClose = nil
            return false
        }
        return true
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
