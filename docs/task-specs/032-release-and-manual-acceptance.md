# Task 032 — Release and Manual Acceptance

Status: In Progress

Created: 2026-08-01

Follows: Tasks 028, 030, and 031

## Outcome

Complete the maintainer-authorized release and human-executed validation for
RelayBar's first Sparkle-enabled build, Settings footer, and corrected popover
insets.

## Delivery Boundary

- Do not commit, push, notarize, publish, change the Homebrew cask, or create a
  release until the maintainer explicitly approves those actions and the
  release version/build.
- The maintainer supplies or approves access to the Sparkle signing key,
  Apple notarization credentials, keyboard/Reduce Motion settings, and an
  actual macOS 13 test environment.
- Use the implementation and local evidence accepted in Tasks 028, 030, and
  031. Any defect found here reopens or creates the appropriate implementation
  task; do not weaken a failed check.
- Keep published archives, appcast entries, direct downloads, and Homebrew
  metadata immutable and mutually byte-identical.

## Work

- Approve a release version/build, commit and push the accepted implementation,
  then build, notarize, staple, and independently verify the final universal
  archive.
- Authorize the Sparkle signing tool, export and restore-test an encrypted
  offline key recovery copy, generate the retained signed appcast, and publish
  it only after its immutable archive is publicly reachable.
- Exercise a prior notarized build through manual and opted-in scheduled update
  checks, including active-tunnel proceed/defer behavior, relaunch, preference
  preservation, and current/offline/malformed/bad-signature/missing-archive/
  downgrade failures.
- Verify release notes, direct download, appcast, extracted app, and Homebrew
  cask resolve to the same signed bytes; cover Gatekeeper, install, update, and
  uninstall behavior before declaring the cask auto-updating.
- In the packaged app, inspect the Settings footer with keyboard navigation,
  Reduce Motion, and larger text, including link behavior, transient copy and
  update feedback, and vertical reachability.
- On macOS 13, inspect New/Edit Profile and a long scrolled rule editor with
  keyboard focus changes and a visible vertical scrollbar; confirm balanced
  insets, no horizontal movement, and reachable controls.

## Acceptance

- The final Developer-ID-signed, notarized, stapled universal archive passes
  Gatekeeper and has matching executable/dSYM UUIDs, release metadata, and
  retained third-party notices.
- The public signed appcast verifies against RelayBar's embedded EdDSA key and
  every retained HTTPS enclosure; the prior notarized build installs and
  relaunches the approved newer build through manual and consented scheduled
  checks without losing preferences.
- Active tunnels never stop without a decision naming their count; proceeding
  completes installation and deferring leaves every tunnel running.
- Current, offline, malformed-feed, bad-signature, signing-continuity,
  missing-archive, and downgrade cases do not replace the app or create
  repeated menu-bar interruptions.
- GitHub release, release notes, direct download, appcast, and Homebrew cask
  identify the same immutable version and archive; Homebrew install, update,
  signature, Gatekeeper, and uninstall checks pass.
- Keyboard navigation traverses the complete Settings footer in a clear order,
  and Reduce Motion introduces no movement-dependent feedback. Larger text
  leaves every control reachable without horizontal clipping or overlap.
- On an actual macOS 13 host, New/Edit Profile and long scrolled content retain
  balanced 16-point insets, vertical-only scrolling, stable focus, and
  reachable controls.
- All approval decisions and manual, accessibility, security, release, and
  live-update evidence are recorded before Task 032 is completed and archived.
