# Task 031 — Edit Profile Insets Verification

Updated: 2026-08-01

Result: Task 031's implementation, regression assertion, light/dark visual
review, and structural minimum-target check pass. Human minimum-host and final
keyboard execution is explicitly deferred to Task 032.

## Evidence

- `PopoverScrollContainer` derives its document width from the actual viewport,
  subtracts balanced 16-point insets, and permits only vertical scrolling.
  `TunnelEditorView` and `SettingsView` share this container.
- The snapshot harness finds the rendered `NSScrollView`, verifies it has no
  horizontal scroller, verifies the document starts at horizontal offset zero,
  and fails if the document is wider than its viewport.
- Opt-in snapshots passed for New Profile, the representative saved Edit
  Profile with Name selected, and Settings in light and dark. The Edit Profile
  evidence at
  `/tmp/relaybar-028-031-snapshots/task-031-edit-profile-{light,dark}.png`
  shows both edges inset and no focus-driven shift.
- The scrolled forwarding-rule fixture also passed the rendered horizontal
  containment assertion in light and dark.
- Existing save/cancel and rule-editor code is unchanged. The fixed header and
  action bar retain their prior alignment while the vertical form remains
  scrollable.
- The GitHub bug template now asks for RelayBar version/build, macOS version,
  Mac architecture, and installation method, and contains no browser or
  smartphone questionnaire.
- The final strict SwiftPM pass executed 222 tests with 15 expected opt-in
  skips and no failures. The universal warnings-as-errors Release build and
  `git diff --check` pass.
- `vtool -show-build .build/RelayBar.app/Contents/MacOS/RelayBar` reports
  `minos 13.0` for both the `x86_64` and `arm64` slices of the signed universal
  app. This proves the deployment boundary structurally; the build host runs
  macOS 27.0.

## Deferred to Task 032

- Repeat focus traversal, long/scrolled rule content, and visible-scrollbar
  review on an actual macOS 13 host as Task 032 evidence.
