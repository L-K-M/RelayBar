# Task 030 — Version and Project Links Verification

Updated: 2026-08-01

Result: Task 030's implementation, automated behavior, and visual acceptance
checks pass. Human keyboard and Reduce Motion execution is explicitly deferred
to Task 032; manual VoiceOver inspection was waived by the maintainer.

## Evidence

- `ApplicationMetadata` derives the app name, marketing version, and build from
  `Bundle.main.infoDictionary` and has stable missing/malformed fallbacks.
  No release identity is duplicated in Swift source.
- `ApplicationAboutModel` routes only the canonical website and GitHub URLs,
  writes the displayed value to the pasteboard, swaps the copy glyph without a
  layout animation, announces success, and clears confirmation after 1.5
  seconds or when Settings closes.
- Six warnings-as-errors focused tests pass for metadata, fallbacks, exact URL
  routing, copy success/failure, announcement, and popover width math.
- The opt-in snapshot harness captured default and approval-required Settings
  at 380 × 440 in light and dark. The default screen visibly has no scrollbar,
  the footer remains near the bottom, and the longest caption remains in the
  vertical scroll flow. Evidence is under
  `/tmp/relaybar-028-031-snapshots/settings-*.png` and
  `settings-login-approval-*.png`.
- `settings-transient-confirmations-*.png` captures the fixed-width checkmark
  and inline **You're up to date.** result without moving the footer.
- Snapshot metadata is fixed to the packaged 1.3.0 build 6 fixture and displays
  `RelayBar 1.3.0 (6)`; production reads the packaged property list.
- The final strict SwiftPM pass executed 222 tests with 15 expected opt-in
  skips and no failures. The universal warnings-as-errors Release build and
  `git diff --check` pass.

## Deferred to Task 032

- Confirm full keyboard traversal and copy feedback with Reduce Motion on in
  the packaged app. Source accessibility semantics and announcement routing
  are covered by implementation and automated tests.
