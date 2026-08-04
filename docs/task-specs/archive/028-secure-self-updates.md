# Task 028 — Secure Self-Updates

Status: Complete

Created: 2026-07-30

Reactivated: 2026-08-01

Issue: [#18 — Add self-update capabilities](https://github.com/lx2026/RelayBar/issues/18)

## Outcome

Implement secure native update checks and installation approval with quiet,
user-controlled scheduling, active-tunnel protection, and release tooling for
RelayBar's first Sparkle-enabled build.

## Delivery Boundary

- Use a pinned, reviewed Sparkle 2 production release and its standard update
  UI; do not build a custom downloader, installer, or GitHub API poller.
- Keep one updater controller for the app lifetime. Add **Automatic Updates**
  as the second row of Settings' existing General card and add a link-weight
  **Check for Updates…** action to Task 030's footer.
- Automatic checks default off. Suppress Sparkle's separate consent prompt;
  the Settings toggle is the sole consent surface. Its supporting copy is
  **Checks about once a week and offers new versions. Nothing installs without
  you.**
- An opted-in scheduled check may present Sparkle's standard update window for
  a newer version and must honor its skip/remind choices. A scheduled
  current-version result or failure stays silent. Do not check whenever the
  popover opens or the app becomes active.
- Keep updater state out of the menu-bar icon, tunnel list, Settings button,
  and list header. Do not add update badges, banners, or persistent last-check
  status.
- Configure the production HTTPS appcast and EdDSA trust boundary, and provide
  tooling that accepts only an immutable universal Developer-ID-signed,
  Apple-notarized RelayBar ZIP.
- Do not invoke Homebrew, guess the installation source, force an update, add a
  beta channel, or silently replace the app without the user's approval.
- Keep Sparkle unavailable under SwiftPM tests through an adapter so tests do
  not start an updater or contact the network.
- Do not ship a placeholder, mock, fallback, or mutable feed. Publishing and
  validating the first production appcast, release, and cask revision require
  maintainer approval and are tracked in Task 032.

## Work

- Integrate `SPUStandardUpdaterController` into the Xcode app behind a testable
  application boundary, including accessory-app activation and relaunch
  behavior.
- Add the scheduled-check preference and manual-check action to Settings. A
  manual check shows inline **Checking…**, **You're up to date.**, or a concise
  retryable failure; announce state changes to VoiceOver and never persist an
  **Up to date** claim across sessions.
- Activate the accessory app when a manual check opens Sparkle's window. Keep
  scheduled failures silent and bounded to logging.
- Before an approved update stops or relaunches RelayBar, detect active
  tunnels, name how many will stop, and provide a safe defer/cancel path. A
  scheduled-check preference alone never authorizes terminating connections.
- Configure the feed URL and public EdDSA key without committing the private
  key, Apple credentials, or any other release secret; send no system profile.
- Configure the scheduled interval to match the Settings promise and verify
  that changing focus or reopening the popover does not reset its cadence.
- Extend the custom build and release scripts to sign Sparkle's nested code
  inside-out, generate the appcast only from the final stapled archive, verify
  every advertised URL and signature, and retain older full-update entries.
- Document key storage and recovery, publication order, the manual bridge from
  pre-Sparkle versions, and Homebrew coordination. Mark the cask as
  auto-updating only after a Homebrew-installed copy passes the full flow.
- Defer Keychain authorization, notarized prior-to-newer live updates,
  production publication, Homebrew execution, and human accessibility checks
  to Task 032.

## Acceptance

- The Xcode app pins one reviewed Sparkle controller for the app lifetime while
  SwiftPM tests use an inert or injected update boundary and make no network
  request.
- Automatic checks are off until enabled in Settings, use Sparkle's
  authoritative preference and seven-day cadence, and show no separate consent
  prompt. Popover presentation and app activation do not trigger checks, and
  the updater sends no system profile.
- The tunnel list, menu-bar icon, and Settings button render identically in all
  updater states; no badge, banner, or last-check label is added.
- A manual check exposes accessible in-place progress and current/error results
  or opens the activated Sparkle window when an update exists.
- With active tunnels, installation cannot stop or relaunch the app until a
  decision names the affected tunnel count and the user explicitly proceeds;
  deferring leaves every tunnel running.
- The production property list contains the canonical feed URL, matching public
  key, signed-feed enforcement, pre-extraction verification, seven-day interval,
  and disabled automatic download/install defaults.
- Release tooling signs Sparkle's nested code inside-out, requires the final
  public archive to match locally, retains full entries, and rejects unsigned
  feeds, mismatched keys, non-HTTPS or malformed enclosures, non-descending
  builds, length mismatches, and invalid EdDSA signatures.
- The Developer-ID-signed universal Release build passes strict nested-signature,
  hardened-runtime, architecture, and executable/dSYM UUID checks.
- Focused tests, strict tests, a warnings-as-errors Release build,
  light/dark Settings evidence, and `git diff --check` pass; affected system
  specs and verification evidence are current before completion.
