# RelayBar Scion

RelayBar Scion is a fork of [lx2026/RelayBar](https://github.com/lx2026/RelayBar), a tiny
native macOS menu-bar app for structured SSH forwarding profiles and exact-path remote
file access. A scion is the cutting taken from a parent plant and grown on separately;
the name says where this came from without claiming to be it.

Current version: <!-- version -->2.0.1<!-- /version -->. [Download](https://github.com/L-K-M/RelayBar/releases/latest).

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
name `com.relaybarscion.RelayBarScion.status`. At every launch the app asserts its
visibility, discards a saved slot that no attached screen can display, and clears the
stale keys the old `MenuBarExtra` item left behind.

**Re-launching the app is an escape hatch.** Opening RelayBar while it is already running
re-asserts the icon and opens the menu, instead of doing nothing.

**The app installs its own main menu,** so ⌘X/⌘C/⌘V/⌘A still reach the text fields in the
profile editor and the Remote Files window after leaving the SwiftUI scene.

This change comes with a trade-off: because visibility is asserted at every launch, ⌘-dragging the
icon off the menu bar does not persist. For an app whose only surface is that icon,
coming back is the safer default.

## Installing alongside upstream

The app carries its own bundle identifier, `com.relaybarscion.RelayBarScion`, so macOS
treats it as a separate application: separate preferences, separate Login Item, separate
Accessibility and Local Network grants, and a separate menu-bar slot. Upstream RelayBar
can stay installed and running.

On its first launch it copies saved forwarding profiles and Remote Files hosts out of
upstream's preferences domain so nothing has to be retyped. It copies rather than moves,
leaving upstream's own preferences intact. Two things do not carry over, because they
belong to the old identity: Launch at Login must be re-enabled, and macOS will ask again
for Accessibility or Local Network access when a connection first needs it.

It also ships no update feed. Upstream's feed and signing key are deliberately absent,
because a build pointing at them would replace itself with upstream's app. You can use
[Obtainintosh](https://github.com/L-K-M/Obtainintosh/) to handle updates.

## Build

Requires macOS 13 or newer and the Xcode command-line tools. This fork has not yet
published a release, so build it yourself:

```bash
./scripts/build.sh
open .build/RelayBarScion.app
```

`scripts/build.sh` is a thin stub over the shared
[release-tool](https://github.com/L-K-M/release-tool) build engine (adding
`--clean`, `--debug`, `--run`, `--install`, `--zip`, `--dmg`); the build itself stays
in `scripts/build-app.sh`, which writes `.build/RelayBarScion.app`. With a
**Developer ID Application** certificate in your login keychain the build is signed
for notarization (set `SIGNING_IDENTITY` to choose one); without one it is ad-hoc
signed — it runs fine on your own Mac and is what CI publishes, but cannot be
notarized.

Releases are cut with `scripts/release.sh X.Y.Z [--push]` (a stub over the same
engine): it bumps the version, build number, and the version line above in one
commit, tags `vX.Y.Z`, and with `--push` lets CI test, build, and publish an
unsigned (ad-hoc-signed) GitHub Release, like the sibling family apps' releases
— Gatekeeper warns on first launch, and the release notes explain the bypass.
Each release also carries an experimental Ubuntu build: `relaybar-tray`, a
system-tray companion that runs the same forwarding profiles from a flat tray
menu (see [docs/system-specs/modules/linux-tray.md](docs/system-specs/modules/linux-tray.md)).

Bundled third-party license text is in
[`THIRD_PARTY_NOTICES.txt`](Sources/RelayBar/Resources/THIRD_PARTY_NOTICES.txt).

## Test

```bash
swift test
```