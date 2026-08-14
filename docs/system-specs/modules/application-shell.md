# Application Shell

RelayBar is a native macOS 13 or newer menu-bar application: an AppKit
`NSStatusItem` owned by the application delegate, presenting a SwiftUI popover.

## Contract

- The app runs as a menu-bar accessory with no Dock icon (`LSUIElement`).
- The delegate creates the status item once at launch, holds it for the process
  lifetime, and gives it the explicit autosave name
  `com.lx2026.RelayBar.status`. The system persists the item's slot and
  visibility under that name in RelayBar's own defaults domain, so the app can
  address, repair, and re-assert its own icon. Visibility is set true at every
  launch, a saved slot that no attached screen can display is discarded before
  the item is created, and the state the earlier `MenuBarExtra` item left under
  the system-assigned name `Item-0` is cleared.
- The menu-bar item is image-only and never lays out a title.
- Re-launching the running app opens the menu and re-asserts the icon rather
  than doing nothing, so a hidden item is always recoverable.
- A main menu supplies the standard editing key equivalents, which an
  `LSUIElement` app otherwise never routes to the first responder.
- The popover is a 380 × 440 point window containing the tunnel list, the profile editor, or the settings screen.
- The profile editor and Settings use one viewport-constrained vertical-scroll
  container. Its document width is the viewport minus balanced 16-point
  insets, so focus rings and intrinsically wide controls cannot create a
  horizontal scroll range or shift content against an edge. Field labels
  appear once; native picker labels are hidden where a custom field label is
  present.
- The menu-bar icon indicates whether any tunnel is starting, retrying, or running. The item's tooltip and accessibility value report the live active tunnel count, so hovering the icon or asking VoiceOver answers "is anything connected?" without opening the menu.
- The list header reports the active tunnel count.
- A labeled Remote Files row below the tunnel list opens or focuses one separate window.
- The Remote Files window uses a 360 × 300 point launcher with server selection and an Add Host action. It expands to 780 × 520 points for browsing, with a 620 × 400 browser minimum. Entering the split preview grows an undersized window to at least 980 × 640 points and applies a 760 × 440 preview minimum; it never shrinks a user-enlarged window, and returning to the browser preserves the current size.
- A gear button in the list header opens an in-popover settings screen with the editor's back-navigation idiom; Escape returns to the list.
- The settings screen's Launch at Login toggle registers or unregisters the main app as the current user's login item through `SMAppService.mainApp` — no helper executable, launch daemon, elevated privilege, or separate settings window.
- The General card's second row is **Automatic Updates**. It controls
  Sparkle's own persisted scheduled-check preference, defaults off, checks at
  a seven-day interval when enabled, and cannot enable automatic download or
  installation. Settings and application activation do not initiate checks.
- The system login-item status is authoritative; no second enabled flag is persisted. Approval-required and not-found states keep the toggle off, while an operation error remains visible without overriding the system-reported toggle state, so failed changes stay truthful and retryable. Approval-required links to the macOS Login Items settings, and the displayed state refreshes when the app becomes active.
- A login launch opens the same menu-bar-only app; saved forwarding profiles stay stopped until the user starts them.
- A quiet Settings footer reads version and build from the running bundle,
  offers a non-shifting copy confirmation, and opens the canonical website and
  GitHub repository. Its **Check for Updates…** action exposes only transient
  checking/current/error text and starts one user-initiated Sparkle check; a
  found update continues in that same check's standard Sparkle window. Closing
  Settings clears inline claims.
- Updater state never changes the menu-bar icon, tunnel-list header, Settings
  button, or list content. Before an update-driven relaunch, active tunnels
  produce a modal decision naming their count: stop them and install, or keep
  them running and defer installation until they are stopped. A deferred
  install remains visible in Settings with its current tunnel count, and the
  installer is resumed only after termination callbacks confirm every managed
  SSH master and control helper has exited. Stop sends SIGTERM, then escalates
  a surviving child to SIGKILL after a bounded grace period so update relaunch,
  quit, logout, and shutdown cannot wait indefinitely.
- A maintainer-only `--maintainer-update-feed` launch argument can override the
  bundled production feed only for an explicit-port, plain-HTTP loopback URL
  on `127.0.0.1`, `localhost`, or `::1`. The override is process-scoped and is
  not persisted. An invalid requested override prevents the updater from
  starting; an ordinary launch uses the signed HTTPS production feed.
- Quit stops all managed SSH processes before terminating the app.

## Ownership

- `RelayBarMain` is the entry point; `RelayBarAppDelegate` owns application
  lifecycle, the status item, and the popover that hosts `RelayBarRootView`.
- `StatusItemDefaults` owns the persisted status-item keys the system writes
  into RelayBar's defaults domain.
- `RelayBarRootView` owns navigation and presentation.
- `TunnelStore.shared` owns tunnel and process state.
- `LaunchAtLoginModel` owns login-item state behind the injected `LoginItemServicing` boundary.
- `UpdateModel` owns the Settings-facing state behind one app-lifetime
  `UpdateServicing` boundary. The Xcode app supplies Sparkle; SwiftPM tests
  supply an inert or injected service and cannot contact the update feed.
- `ApplicationAboutModel` owns bundle metadata, version copying, and canonical
  project-link routing.
- `RemoteFilesWindowController.shared` owns the Remote Files window.
