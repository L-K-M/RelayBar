# RelayBar

A fork of [lx2026/RelayBar](https://github.com/lx2026/RelayBar), a tiny native macOS
menu-bar app for structured SSH forwarding profiles and exact-path remote file access.

Start at the
[upstream README](https://github.com/lx2026/RelayBar#readme) for what RelayBar does, how
to install a release, and the full documentation.

## Why this fork exists

This fork improves how reliably the app is able to show its menubar icon.

RelayBar is an `LSUIElement` agent, so it has no Dock icon and no window, and its only
surface was a SwiftUI `MenuBarExtra`. `MenuBarExtra` owns its `NSStatusItem` privately
and exposes neither `autosaveName` nor `isVisible`. macOS persists that item's menu-bar
slot and its visibility into the app's own preferences, under a name it assigns by
creation order, and restores both on every later launch. So once the icon had been
recorded as hidden — by a stray ⌘-drag, a menu-bar manager, or a slot no attached display
can draw — the app could neither detect it nor undo it.

## What this fork changes

**The application delegate owns the status item.** It is created once at launch and held
for the process lifetime, as AppKit menu-bar apps normally do it, rather than being
managed by a SwiftUI scene. The app moves off the SwiftUI `App` lifecycle to a plain
`NSApplication` one so that ownership is real rather than nominal.

**The item has a stable identity the app can address.** It carries the explicit autosave
name `com.lx2026.RelayBar.status`. At every launch RelayBar asserts its visibility,
discards a saved slot that no attached screen can display, and clears the stale keys the
old `MenuBarExtra` item left behind.

**Re-launching the app is an escape hatch.** Opening RelayBar while it is already running
re-asserts the icon and opens the menu, instead of doing nothing.

**The app installs its own main menu,** so ⌘X/⌘C/⌘V/⌘A still reach the text fields in the
profile editor and the Remote Files window after leaving the SwiftUI scene.

This change comes with a trade-off: because visibility is asserted at every launch, ⌘-dragging the
icon off the menu bar does not persist. For an app whose only surface is that icon,
coming back is the safer default.

## Build

Requires macOS 13 or newer and the Xcode command-line tools. This fork publishes no
releases, so build it yourself:

```bash
./scripts/build-app.sh
open .build/RelayBar.app
```

The script writes `.build/RelayBar.app` and signs it with the first valid **Developer ID
Application** certificate in your login keychain; set `SIGNING_IDENTITY` to choose a
different one.

Bundled third-party license text is in
[`THIRD_PARTY_NOTICES.txt`](Sources/RelayBar/Resources/THIRD_PARTY_NOTICES.txt).

## Test

```bash
swift test
```