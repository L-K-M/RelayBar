# Verification

## Required checks

- Run `swift test` for the complete forwarding parser matrix, migration,
  typed-profile and group-tag validation, grouping and metadata-only mutation
  behavior, group lifecycle batching, control sequencing, rollback and
  timeout, runtime port mapping, socket refusal, retry, cancellation, browser
  URL behavior, login-item state mapping, bundle-about behavior, update-state
  mapping through the injected no-network boundary, Remote Files connection
  reuse and cleanup, navigation, path/argument handling, listing parsing,
  Markdown compatibility, link policy, and renderer limits. Tests never read
  or change the real login-item registration and never start Sparkle.
- Build the Xcode app target with complete Swift strict-concurrency checking and warnings treated as errors.
- Run `plutil -lint` against the application property list.
- Run `git diff --check` before committing.

## Pull request review automation

Non-draft pull requests from branches in this repository trigger an optional
GLM 5.3 review on open, reopen, synchronization, and transition out of draft.
The workflow uses `pull_request_target` so it can read the `ZAI_API_KEY` secret
and publish review feedback, but it never checks out or executes pull-request
code and rejects fork pull requests. The review action is pinned to an
immutable commit. Superseded runs for the same pull request are canceled, and
the workflow exits successfully without a review when `ZAI_API_KEY` is not
configured.

## Optional live check

Set `RELAYBAR_LIVE_TEST=1` and `RELAYBAR_LIVE_SSH_HOST` to test a real SSH forward and HTTP response on local port 3000.

Set `RELAYBAR_FLEXIBLE_LIVE_TEST=1` with `RELAYBAR_LIVE_SSH_HOST` to verify that a real RelayBar-managed Local Unix listener reaches Running with the configured mode and is removed on stop.

Flexible-forwarding changes additionally require a live OpenSSH control workflow. Exercise Local SOCKS with client-side hostname delegation, Remote SOCKS with allowed and denied `PermitRemoteOpen` destinations, repeated remote port-`0` allocation, and each server-supported fixed TCP/Unix matrix. Record server-controlled `GatewayPorts` or Unix-socket limitations instead of silently skipping them.

Set `RELAYBAR_REMOTE_FILES_LIVE_TEST=1`, `RELAYBAR_LIVE_SSH_HOST`, and
`RELAYBAR_LIVE_REMOTE_PATH` to run the opt-in Remote Files path test against a
real saved-server target. Add `RELAYBAR_LIVE_SSH_IDENTITY_FILE` when that saved
connection uses an explicit identity. Use `RELAYBAR_LIVE_REMOTE_EXPECT_NONEMPTY=1`
for a nonempty folder or `RELAYBAR_LIVE_REMOTE_EXPECT_FILE=1` for a directly
previewable Markdown file.

Remote Files changes should additionally exercise that server and absolute path manually for nested navigation, cached Back and revisit, uncached-open cancellation, refresh, file download, recursive folder download, cancellation, image preview, Markdown preview, connection loss, window close, and representative failures. For transport-reuse changes, record cold initial-open and at least five warm uncached nested-folder timings against a genuinely high-latency server, and confirm the warm operations reuse one master without another key exchange or authentication.

Before a live server is available, use the DEBUG-only Remote Files fixture to review light and dark appearance, minimum-window truncation, empty folders, long names, immediate target-path and **Opening folder…** feedback, cached revalidation, rapid navigation and Back cancellation, split image and Markdown previews, sibling selection, Left/Right switching, sidebar dragging and Control-Command-S visibility, focused reading, refresh recovery, initial connection errors, and active, completed, failed, and canceled transfers. Fixture downloads must remain inside their private temporary directory and must not open Finder.

Start a DEBUG build with `--preview-window --flexible-forwarding-preview` to review rule-aware profile rows and the editor without reading or changing the user's saved profiles. Review add, type switching, duplicate, reorder, remove, automatic ports, Unix fields, exposure warnings, reverse-SOCKS policy, scrolling, keyboard focus, and accessibility labels in light and dark appearance.

Start a DEBUG build with `--preview-window --grouping-preview <scenario>` to review saved-profile grouping without reading or changing the user's saved profiles. Supported scenarios are `empty`, `zero-tag`, `all-untagged`, `one-bucket`, `mixed`, `all-tagged`, `long-tag`, and `many-sections`. Review the flat-list threshold, section order, Ungrouped placement, long-label truncation, scrolling, picker and row-menu parity, inline Return/Escape behavior, rename, ungroup-all, the Start All/Stop All/Restart All commands with state-aware enablement, keyboard focus, and accessibility labels in light and dark appearance.

Launch at Login changes require a signed packaged build verified manually for enable, login relaunch as the menu-bar-only app with every saved profile stopped, disable without quitting the running app, and state synchronization after changes made directly in System Settings. Use the offscreen snapshot harness for the settings screen and its approval-required caption in light and dark appearance.

For a native live-transport review without changing the user's saved tunnels, start a DEBUG build with `--remote-files-live-preview <ssh-host>`. This route uses the real SFTP service while keeping review downloads inside the same private temporary directory and suppressing Finder launch.

Markdown changes should exercise a local fixture in light and dark appearance for GFM, properties, callouts, code highlighting/copy, math, footnotes, blocked images/embeds, wiki links, inert tags, Mermaid source, raw HTML, keyboard return, and accessibility reading order.

Changes to bundled renderer resources should build the Xcode app in Debug and Release, verify that Highlighter retains only its formatter and the `github`/`github-dark` themes, verify that SwiftMath retains only Latin Modern metrics/font and licenses, record the Release app and executable sizes, match the stripped executable to its dSYM UUID, and exercise the affected renderer in the native fixture.

Release changes should additionally verify the code signature and notarized app with the scripts in [Build and release](build-and-release.md).

Updater changes additionally require `scripts/verify-update-feed.sh`, nested
Sparkle signature inspection, and a staged prior-to-newer production-equivalent
flow. Exercise manual and opted-in scheduled checks, current/offline/malformed/
bad-signature/missing-archive/downgrade cases, active-tunnel proceed and defer,
preference preservation, relaunch, and Homebrew install/update/uninstall. Feed,
release, and cask publication remain deployment actions requiring approval.
Before publication, use `scripts/stage-private-update.sh` and the guarded
loopback maintainer feed to exercise the signed prior-to-newer flow without a
public asset. Verify that a manual check fetches once, presents the standard
Sparkle UI, installs the newer notarized build, and restores the prior build
after the rehearsal. Use macOS UI automation where it can
observe and operate the installed app; record any unautomated acceptance item
in Task 032 rather than treating it as completed.
