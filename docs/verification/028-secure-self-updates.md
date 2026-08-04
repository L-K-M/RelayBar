# Task 028 — Secure Self-Updates Verification

Updated: 2026-08-01

Result: Task 028's implementation and local acceptance checks pass. Production
release, Keychain-authorized signing, live-update, Homebrew, and human
keyboard/Reduce Motion evidence are explicitly deferred to Task 032.

## Implemented evidence

- The Xcode target pins Sparkle 2.9.4 exactly. SwiftPM has no Sparkle
  dependency; its update boundary is inert or injected and makes no network
  request.
- The shipping property list requires a signed appcast and pre-extraction
  verification. The release verifier authenticates the feed itself before it
  downloads or verifies any enclosure.
- One app-lifetime standard updater starts after application launch. Settings
  reads and writes Sparkle's authoritative automatic-check preference; the
  property list defaults it off, sets a 604,800-second interval, suppresses the
  separate consent prompt, and disallows automatic download/install.
- Manual checks map to transient checking/current/retry states with
  accessibility announcements. A found update activates the app and opens
  Sparkle's standard UI. Closing Settings suppresses late current/error claims.
- Scheduled checks are not connected to popover presentation or application
  activation. The delegate returns an empty system-profile allowlist, and
  updater state does not enter the menu-bar icon, tunnel list, list header, or
  Settings button.
- `UpdateRelaunchGate` names the active tunnel count and provides explicit
  stop-and-install or install-after-tunnels-stop decisions. Deferral retains
  every connection; stopping the last tunnel or quitting hands control back to
  Sparkle.
- Update-model tests cover authoritative preference storage, check coalescing,
  current/failure/available mapping, session-transient claims, the unavailable
  boundary, and active-tunnel proceed/defer/quit behavior.
- The tunnel-list snapshot is byte-identical with idle and current-result
  updater state in both appearances, proving no updater badge, banner, or
  Settings-button change entered that surface.
- The release build script signs Sparkle's nested XPC services, Autoupdate,
  Updater, and framework inside-out. Appcast tooling verifies the immutable
  public archive byte-for-byte, preserves all full-update entries, and checks
  each HTTPS enclosure's positive length, strictly descending numeric build,
  and EdDSA signature. Verification also rejects a Keychain signing key that
  does not match the app's committed `SUPublicEDKey`.
- The committed public key matches Keychain account
  `com.lx2026.RelayBar`. The independently downloaded 1.3.0 archive matched its
  published 5,389,681-byte length and SHA-256
  `127670e8e5afa51e92ea65c51ca3f56144f85b7f54bda218d517b3dd4f17aa7a`.
- The universal warnings-as-errors Release build passed for `arm64` and
  `x86_64`. The Developer ID build then passed strict verification for the app,
  Sparkle framework, both XPC services, and Updater; executable and dSYM UUIDs
  match for both slices.
- The rebuilt signed app contains both signed-feed policy keys, starts cleanly
  from the CLI with automatic checks off, and emits no startup error.
- The final strict SwiftPM pass executed 222 tests with 15 expected opt-in
  skips and no failures. Property-list validation, shell syntax checks, and
  `git diff --check` pass.

## Deferred to Task 032

- Allow the Sparkle signing tool to use the Keychain private key, create and
  verify the retained signed appcast, and create/test an encrypted offline key
  recovery copy outside the repository.
- With explicit deployment approval, create a higher-version universal
  Developer-ID-signed and notarized staging release, publish its immutable
  archive and appcast in the documented order, then update from a prior
  notarized build by both manual and opted-in scheduled checks.
- Record current, offline, malformed-feed, bad-signature, missing-archive,
  downgrade, preference preservation, active-tunnel proceed/defer, relaunch,
  Gatekeeper, dSYM, Homebrew update/uninstall, and byte-identity evidence.
