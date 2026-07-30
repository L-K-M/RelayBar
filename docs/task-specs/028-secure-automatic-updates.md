# Task 028 — Secure Automatic Updates

Status: Proposed

Created: 2026-07-30

## Outcome

Let RelayBar detect stable updates quietly, offer an explicit **Check for
Updates…** action, and install approved updates through a familiar native Mac
flow. Direct downloads and the Homebrew cask must use the same signed,
notarized release archive and version authority.

Use [Sparkle 2](https://sparkle-project.org/documentation/) rather than a
custom GitHub API poller or installer. Its standard updater already provides
scheduled checks, appcast version comparison, EdDSA verification, safe bundle
replacement, relaunch, and menu-bar-app-friendly reminders.

## Delivery Boundary

### Included

- A pinned, reviewed Sparkle 2 dependency in the Xcode app, isolated behind an
  adapter that does not start or mutate updater state under SwiftPM tests.
- One app-lifetime updater controller, Sparkle's standard update UI, a manual
  check in Settings, and user-controlled scheduled background checks.
- A static HTTPS appcast, signed update metadata, release notes, and the
  existing universal Developer-ID-signed, notarized ZIP as the full update.
- Release automation that generates and verifies the appcast only from the
  final stapled archive, without placing the EdDSA private key in the
  repository or command output.
- Coordination with Task 023 so Homebrew `livecheck` reads the same stable
  version authority and the cask declares `auto_updates true` only after the
  in-app updater downloads and installs updates itself.

### Excluded

- A custom updater protocol, GitHub API polling, invoking `brew` from RelayBar,
  or changing behavior based on a guessed installation source.
- Forced updates, silent installation without user choice, beta channels,
  phased rollout, delta archives, package installers, and a custom release
  notes hosting pipeline.
- Publishing an appcast, release, or cask without separate deployment
  approval.

## Work

### 1. Add the native update experience

- Integrate `SPUStandardUpdaterController` once in the app lifecycle and
  expose its availability and actions through a small testable adapter.
- Add **Check for Updates…** and an **Automatically check for updates**
  preference to Settings. Use Sparkle's standard second-launch consent and
  scheduler instead of checking on every activation of the menu-bar popover.
- Send no system profile. Keep network failure and the no-update state quiet;
  use Sparkle's standard accessible UI only when the user checks manually or a
  newer version is available.
- Configure `SUFeedURL`, `SUPublicEDKey`, and monotonically increasing
  `CFBundleVersion` values without embedding a private key or credential.
- Choose the HTTPS appcast path as a long-lived compatibility commitment:
  every shipped build must keep reaching it even if the project website moves.
- Verify Sparkle's consent and update windows activate correctly from
  RelayBar's accessory-policy `MenuBarExtra` application.

### 2. Make one secure release authority

- Replace the current flat outer-bundle signing step with explicit inside-out
  Developer ID signing of Sparkle's framework and helper components, using the
  hardened runtime and trusted timestamps before signing RelayBar itself.
- Extend the release workflow to take the final stapled ZIP, generate its
  EdDSA signature and appcast entry, attach release notes, and validate every
  advertised URL before publication.
- Link release notes to the immutable GitHub release page instead of building a
  second notes publication system.
- Publish in an order that never advertises a missing, mutable, unsigned, or
  unnotarized archive. Preserve prior entries so installed versions retain a
  valid full-update path.
- Document EdDSA key creation, Keychain storage, appcast generation, and the
  rule that version/build numbers advance before release. Losing or
  compromising the private key requires another manually installed bridge
  release because existing apps cannot receive a new public key in-band.
- Treat the first Sparkle-enabled release as a manual bridge: existing builds
  without Sparkle cannot discover it in-app and must update once by direct
  download or Homebrew.

### 3. Keep Homebrew coherent

- Update Task 023 and the cask design to use the immutable release ZIP and
  appcast-backed `livecheck`.
- Add Homebrew's `auto_updates true` stanza only when the shipped Sparkle flow
  performs the download and installation; a link-only update notice does not
  qualify.
- Verify that a Homebrew-installed copy can complete a Sparkle update and that
  later `brew upgrade --cask relaybar` and uninstall operations remain
  consistent.
- Ship the first cask without `auto_updates`; prepare that stanza as a later
  cask revision only after the Homebrew-installed end-to-end update succeeds.

## Acceptance

- An older notarized RelayBar build detects a newer staging-appcast entry both
  through **Check for Updates…** and through the consented scheduled check.
- The standard update flow verifies the EdDSA signature and Apple code
  signature, installs the universal notarized bundle, relaunches RelayBar, and
  preserves tunnels and preferences.
- A current version, offline host, malformed appcast, wrong EdDSA signature,
  code-signing continuity failure, downgrade, or missing archive fails safely
  without replacing the application or producing repeated menu-bar
  interruptions.
- Release validation refuses to publish an appcast entry for an archive that
  lacks the expected universal architectures, nested signatures, hardened
  runtime, matching dSYM UUIDs, accepted notarization, or stapled ticket.
- Automatic checking remains user-controlled, sends no system profile, and
  does not run on every popover activation.
- The appcast, direct download, release notes, and Homebrew cask resolve to the
  same stable version and immutable archive; extracted bytes and SHA-256 match
  the verified release.
- Homebrew `livecheck`, style, audit, install, Sparkle-update, subsequent
  upgrade, and uninstall checks pass on the supported architecture boundary.
- Strict tests, a warnings-as-errors Release build, Sparkle's production update
  test, Gatekeeper assessment, accessibility inspection, and
  `git diff --check` pass.
- System specs describe updater lifecycle, privacy, trust, release ordering,
  Homebrew coordination, recovery, and the manual first-update bridge before
  this task is marked Complete.
- No private update key, Apple credential, notarization profile, secret,
  mutable latest-download URL, or local path is committed or published.
