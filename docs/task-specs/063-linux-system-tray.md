# Task 063 — Linux System Tray (Ubuntu)

Status: In Progress

Created: 2026-08-25

## Outcome

A Ubuntu user can install a `.deb`, get a system-tray icon (StatusNotifierItem
via libayatana-appindicator), and start/stop their saved SSH forwarding
profiles from a flat tray menu, with automatic retry and failure notices,
using the same profile model and SSH argument policy as the macOS app.

## Delivery Boundary

- Extract the portable engine (`Tunnel`, forwarding endpoint models,
  `SSHArgumentPolicy`/`SSHMasterPolicy`, `SSHCommandFormatter`,
  `SSHControlPath`, retry backoff) into a Foundation-only `RelayBarCore`
  library target consumed by both apps.
- Add a Linux-only executable target `RelayBarTray`: GLib main loop +
  libayatana-appindicator3 through a small C shim, an XDG-config profile
  store (`~/.config/relaybar/tunnels.json`, a plain `[Tunnel]` JSON array),
  and a per-profile process supervisor that mirrors the macOS master
  arguments (`-N -T -M -S`, enforced options, bind mask) and retry schedule.
- The tray menu is flat: one toggle item per profile with phase text, plus
  Reload Profiles and Quit. No editor UI, no Remote Files browser, no
  markdown preview, no Sparkle-equivalent updater.
- The Linux build installs forwards monolithically on one ssh invocation
  (`ExitOnForwardFailure=yes`); it does not replicate the staged
  control-channel rule installation or runtime port resolution of the
  macOS app (task 037).
- CI gains a Linux job that builds the tray product with warnings as errors;
  releases gain an amd64 `.deb` asset uploaded to the existing tag's release
  under the same immutability rules (no clobber, byte-compare verification).
- No changes to the macOS app's behavior or release artifacts beyond linking
  `RelayBarCore`.

## Work

- Move `Tunnel.swift`, `SSHArgumentPolicy.swift`, `SSHCommandFormatter.swift`,
  and `SSHControlPath.swift` to `Sources/RelayBarCore`, making their
  cross-module surface public; port `mkdtemp`/signal imports off `Darwin`.
- Add the `CAppIndicator` system-library shim (module map + inline C helpers)
  so Swift never names C enum enumerators or GTK macros directly.
- Implement `ProfileStore`, `TunnelSupervisor` (start/stop/retry/SIGTERM
  escalation, stderr captured to a per-attempt temp file), and
  `TrayMenuController`; marshal all GTK work onto the GLib main loop.
- Add `scripts/package-deb.sh`; extend `ci.yml` and `release.yml`.
- Update README, CHANGELOG, and system specs (new `modules/linux-tray.md`,
  index entry).
- Add portable `RelayBarCoreTests` covering argv assembly parity, argument
  policy, and control-path length guards.

## Acceptance

- `swift build -c release --product RelayBarTray` succeeds on Ubuntu 22.04
  with only `pkg-config` + `libayatana-appindicator3-dev` installed.
- The produced `.deb` installs `/usr/bin/relaybar-tray`; launching it shows a
  tray icon whose menu lists profiles from `tunnels.json`; toggling starts or
  stops the matching ssh master; a failing profile retries with visible
  countdown-free phase text and stops after the retry budget.
- `swift test` on macOS still passes unchanged, including new core tests.
- A published tag carries both `RelayBarScion.zip` and the `.deb`, and the
  uploaded deb byte-matches the built artifact.
