# Task 053 — Auto-start Profiles at Launch

Status: In Progress

Created: 2026-08-15

## Outcome

Let users mark individual saved forwarding profiles to start automatically when
RelayBar launches, without starting profiles that are not marked.

## Delivery Boundary

- Persist a per-profile **Start at Launch** flag as part of the existing v2
  saved-tunnel JSON in `UserDefaults`.
- Expose the flag in the profile editor's connection details and in the row
  menu as a checkmark action.
- At application launch, start every saved profile whose flag is on through the
  existing per-profile lifecycle. Leave unmarked, already-active, and unsafe
  profiles to their existing behavior: unmarked and already-active profiles are
  skipped, and an unsafe marked profile fails visibly on its own row.
- Toggling the flag from the row menu is metadata-only and must not stop or
  relaunch an active profile.
- Do not add a global "start all at login" setting, a second process manager,
  or any auto-start behavior for debug preview launches.
- Do not change the existing Launch at Login behavior beyond the settings
  caption that now describes the new flag.

## Work

- Add a decoded-with-default `startsAtLaunch` field to `Tunnel`, preserving
  compatibility with already-saved v2 records that do not contain the key.
- Add `TunnelStore.startProfilesMarkedForAutoStart()` and
  `TunnelStore.setStartsAtLaunch(_:for:)`.
- Call the auto-start entry point from `applicationDidFinishLaunching` only
  when the launch is not a debug preview launch.
- Add the editor switch and row-menu action, with keyboard and VoiceOver
  support matching the existing settings and row-menu controls.
- Update Settings copy, the application-shell, tunnel-management, and
  data-and-state system specs, and the task index.
- Add focused store tests for auto-start selection, metadata-only toggling,
  and decoding records that predate the flag.

## Acceptance

- A profile created or edited with **Start at Launch** enabled is started when
  the app finishes launching; an unmarked profile stays stopped.
- Toggling **Start at Launch** in the row menu while a profile is running
  leaves it running and persists the new value.
- Profiles saved before the flag existed still load with the flag off.
- An unsafe marked profile follows the existing visible-failure path and does
  not block other profiles.
- The editor control and row-menu action are keyboard- and VoiceOver-operable,
  and Settings copy no longer claims that all profiles stay stopped at launch.
- `swift test -Xswiftc -warnings-as-errors`, the Release build, and
  `git diff --check` pass.
- No release or deployment occurs without separate approval.
