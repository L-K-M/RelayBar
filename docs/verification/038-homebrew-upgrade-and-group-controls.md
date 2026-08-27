# Task 038 — Homebrew Upgrade and Group Controls Verification

Verified: 2026-08-27

Result: Implementation, automated checks, visual snapshots, signed build, cask
validation, running and stopped upgrade behavior, and data preservation pass.
The signed candidate was installed, reviewed, and accepted by the maintainer.

## Group controls

- `TunnelGroupActionAvailabilityTests` passes four stopped, active, mixed, and
  empty-state cases. The visible buttons call the existing `startGroup` and
  `stopGroup` paths; the lifecycle implementation is unchanged.
- `swift test -j 1 --no-parallel -Xswiftc -warnings-as-errors` passes all 274
  tests with 17 expected opt-in skips and no failures.
- `VisualSnapshotHarness/testCaptureTask038GroupControlSnapshots` passes and
  creates eight temporary 380 × 440 captures: stopped, active, mixed, and long
  name in Aqua and Dark Aqua. The rendered containment assertion passes for
  every capture. Inspection confirms both persistent controls remain at the
  trailing side before the actions menu and long names truncate before them
  without horizontal overflow.
- Start All is enabled for inactive members, Stop All is enabled for lifecycle-
  active members, and a mixed group enables both. Restart All, Rename Group,
  and Ungroup All remain in the menu. Both visible buttons have group-specific
  help and accessibility labels.

## Homebrew cask

- The tap cask contains `uninstall quit: "com.lx2026.RelayBar"` and no signal,
  script, `zap`, or data-removal directive. `ruby -c`, `brew style --cask`, and
  `brew livecheck --cask lx2026/tap/relaybar` pass; livecheck reports 1.5.0 as
  current.
- Homebrew 6.0.19 stores uninstall artifacts in the installed cask receipt. A
  deliberately recreated legacy 1.4.0 receipt without the quit directive
  confirms that changing the tap does not alter the old receipt: upgrade
  installs 1.5.0 (9), but the old PID 8673 stays running. This transition is
  recorded as an expected legacy limitation, not a pass. An existing legacy
  install needs one reinstall or manual quit before its first later upgrade.
- A 1.4.0 fixture installed with the updated receipt records both the app and
  `quit: com.lx2026.RelayBar`. During the real running-app upgrade, Homebrew
  reports a successful quit, PID 11793 exits, 1.5.0 build 9 replaces the
  bundle, and Homebrew reopens exactly one healthy RelayBar process as PID
  12030. The new PID differs from the old PID and reaches a normal AppKit event
  loop.
- With RelayBar initially stopped and the same updated 1.4.0 receipt, the real
  1.4.0-to-1.5.0 cask upgrade succeeds, installs build 9, and leaves no RelayBar
  process running.
- The official upgraded app executable SHA-256 is
  `5f3d8a4f751752fe8a7db36fc18cbac18cc6ecccd4d36288864e22d3602cca73`.
  It is universal `x86_64 arm64`, passes strict nested code-signature
  verification and stapler validation, and Gatekeeper reports `Notarized
  Developer ID`.
- `brew audit --cask --online --signing` is blocked before auditing the cask:
  Homebrew requires Xcode 27.0 on this macOS 27 host, while the installed Xcode
  is 26.6. Syntax, style, livecheck, real installation, and the available
  signature checks pass independently.

## Data and installed review candidate

- Before and after the cask install/uninstall/upgrade matrix, the preferences
  SHA-256 remains
  `148aa35a292d86c5d8ee58a2b296e56aca56bf31e442c63a536c5f72b86b8798`.
  Application Support remains 276 files with aggregate content-manifest hash
  `7d1d72cb90c4009d85611c486b8edb1639a39930f64ce02ca8855d13d9c81d7a`.
- The universal Release candidate builds with warnings as errors and is signed
  with the repository's Developer ID Application identity. Every nested
  Sparkle boundary and the final bundle pass strict signature verification;
  `Packaging/Info.plist` passes `plutil -lint`.
- The byte-identical signed candidate is restored at
  `/Applications/RelayBar.app` as version 1.5.0 build 9 after the cask rehearsal
  and was running as PID 13411 with a healthy AppKit event loop. The maintainer
  accepted the installed UX. No commit, push, cask publication, release, or
  issue mutation was performed as part of Task 038.
