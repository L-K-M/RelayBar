# Linux System Tray

Implemented behavior of `relaybar-tray`, the Linux companion executable introduced by
[task 063](../../task-specs/archive/) once accepted. Source code remains authoritative.

## Shape

RelayBar Scion on Linux is a second front end over the shared engine:

```
macOS app (AppKit/SwiftUI)          relaybar-tray (GTK/AppIndicator)
        │                                     │
        └────────────► RelayBarCore ◄─────────┘
   Tunnel model · SSHArgumentPolicy/SSHMasterPolicy · SSHControlPath
   SSHMasterInvocation · TunnelRetryPolicy
```

- `RelayBarCore` is Foundation-only and builds on both platforms.
- Platform services stay out of the core: launch-at-login and Sparkle have no
  Linux counterpart here; notifications go through `notify-send` when present.

## Profiles

- Stored at `$XDG_CONFIG_HOME/relaybar/tunnels.json` (default
  `~/.config/relaybar/tunnels.json`) as a JSON array of `Tunnel` records — the
  same encoding the macOS app persists, so records can be copied across.
- Profiles failing `Tunnel.isSafeToRun` are never shown or started.
- Writes are atomic (temp file + replace).

## Tray menu

- One checkbox item per profile; checked = lifecycle-active
  (`starting`/`retrying`/`running`). Clicking toggles start/stop.
- Phase text rides the label (`starting…`, `retry n/10`,
  `failed (select to retry)`).
- Fixed items: **Reload Profiles** and **Quit**.
- The whole menu is rebuilt per state change; profile counts make this cheap
  and it avoids DBusMenu partial-update quirks.

## Process model

- One ssh master per active profile: `-N -T -M -S <control socket>` plus the
  enforced options from `SSHMasterPolicy`, bind-mask/unlink options,
  `PermitRemoteOpen`, then forwarding flags, additional arguments, host.
- Unlike macOS (staged control-channel installs), forwards ride this single
  invocation; `ExitOnForwardFailure=yes` turns bind failures into exits.
- stderr is captured to a temp file under the profile's private control
  directory; the tail feeds failure text. Retry uses the shared
  `TunnelRetryPolicy` schedule (1s doubling to a 60s cap, 10 attempts).
- Stop sends SIGTERM with a 3s grace before SIGKILL. SIGINT/SIGTERM to the
  tray stop all masters before exit.
- Reload refreshes stopped definitions; running masters keep their argv so a
  reload can never silently rewrite live forwarding rules.

## Build and release

- `swift build -c release --product RelayBarTray` on Ubuntu 22.04 with
  `pkg-config` and `libayatana-appindicator3-dev`; GTK3 arrives transitively.
- CI compiles the tray product with warnings-as-errors on every PR.
- Releases attach `relaybar-tray_<version>_amd64.deb` (see
  [build-and-release](operations/build-and-release.md)); assets follow the same
  immutability rules as the macOS zip.

## Known limitations

- Flat menu only: no editor UI, Remote Files browser, markdown preview, or
  runtime-port display for port-0 remote forwards.
- No autostart integration beyond the desktop's own startup mechanism.
