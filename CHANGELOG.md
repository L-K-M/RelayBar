# Changelog

Notable RelayBar Scion changes are recorded here.

## [Unreleased]

### Changed

- Tag-triggered releases now publish an **unsigned, ad-hoc-signed**
  `RelayBarScion.zip` — the same release model as the sibling family apps
  (maintainer decision, task 062) — instead of failing closed on absent
  Developer ID and App Store Connect secrets. Gatekeeper warns on first
  launch; the release notes explain how to open the app. The
  maintainer-local notarized pipeline is unchanged and still refuses ad-hoc
  builds.
- This fork is now **RelayBar Scion**, with its own bundle identifier
  (`com.relaybarscion.RelayBarScion`), bundle name, and `RelayBarScion.app`
  executable. It installs and runs alongside an upstream RelayBar instead of
  fighting it for the same identity, preferences domain, and menu-bar slot.
- On its first launch, Scion copies saved profiles and Remote Files hosts out
  of upstream's `com.lx2026.RelayBar` preferences domain, so an existing
  RelayBar user starts with their tunnels rather than an empty list. The copy
  runs once, never overwrites anything already saved under the new identity,
  and leaves upstream's domain untouched — the original app keeps working.
  Launch at Login and macOS privacy grants are per-identity and do not carry
  over; both are re-established from Settings and the usual system prompts.
- Scion ships no update feed and no update-signing key. Upstream's feed
  advertises upstream's app, so keeping it would have handed every Scion user
  an update that replaced their build with the one they forked away from.
  Sparkle therefore never starts, **Check for Updates…** stays disabled, and
  new versions are installed by hand until this fork publishes a feed of its
  own.
- Editing an active profile now restarts it with the new definition instead of
  leaving it stopped. The editor's save button is labeled Save & Restart while
  the profile owns lifecycle work, so the restart is disclosed at the decision
  point.
### Added

- Tunnels come back on their own after a VPN connects or disconnects. RelayBar
  now watches the network path: a change ends any pending retry backoff at
  once (with a fresh attempt count, a few times per retry ladder), and a profile
  whose retries ran out during the VPN session — the ladder gives up after
  about five minutes, which every VPN session outlasts — is started again as
  soon as the network changes. The exhaustion message and notification say
  so. Running connections are never restarted on a path change, so a
  split-tunnel VPN that leaves the host reachable keeps its sessions;
  stopping, editing, or deleting a failed profile withdraws it from the
  automatic retry.
- The family release tooling: `scripts/release.sh` and `scripts/build.sh` are
  thin stubs over the shared engines from
  [release-tool](https://github.com/L-K-M/release-tool). One command bumps the
  version, the Sparkle build number, and the README version line together,
  commits, and tags; a new tag-triggered workflow then tests, builds,
  packages, and publishes the GitHub release, and verifies the
  published archive byte-for-byte. The app's version is now single-sourced in
  the Xcode build settings instead of hand-synced literals in the property
  list.
- Builds no longer require a Developer ID certificate: without one,
  `build.sh`/`build-app.sh` fall back to an ad-hoc-signed app (same inside-out
  signing order) that runs locally, like the sibling apps' dev builds.
  CI releases are ad-hoc signed too — same model as the sibling apps'
  releases, with release notes explaining the Gatekeeper bypass — while
  `notarize-release.sh` still refuses an ad-hoc build outright, keeping the
  notarized pipeline honest.
- Profiles can be duplicated from the row menu. The copy gets fresh profile
  and rule identities, lands right after the original, and starts stopped —
  clone-then-tweak without retyping a connection.
- Profiles can be marked **Start at Launch** in the editor or row menu, and
  RelayBar starts those profiles automatically when it launches.
- Row menus can copy a profile as the `ssh` command RelayBar effectively
  runs — same grammar Quick Add imports, so the command pastes straight back
  or into a terminal.
- The profile editor says exactly why Save is disabled — the first blocking
  issue, next to the button and as its tooltip — instead of making you hunt
  a dozen fields.
- Round icon buttons deepen on hover, the row's ⋯ menu matches its sibling
  buttons, and truncated SSH errors expand in a hover tooltip.
- Symbolic links in Remote Files now behave like what they point at: linked
  folders navigate, linked Markdown and images preview, and other linked
  files download — instead of failing as a download error.
- A profile that exhausts automatic retries posts one system notification,
  so a tunnel that gives up while the popover is closed is never silent.
- Remote Files remembers the last path each connection opened successfully
  and offers it in the launcher — on a fresh window and when switching
  servers with the field untouched.
- Remote Files now follows `Include` lines in `~/.ssh/config` (glob
  patterns, `~/` and `~/.ssh`-relative resolution, depth- and file-capped),
  so hosts kept in included files appear in the server list.
- Quitting with tunnels running asks first — Stop and Quit, or Cancel — so a
  stray ⌘Q no longer drops every live connection without warning.
- Quick Add notices a complete SSH command on the clipboard and offers
  one-click import (or ⇧⌘V) — copy a command anywhere, open RelayBar, done.
  The clipboard is read only when the chip is clicked, so the system's
  paste-permission prompt can never appear from opening the editor.

### Fixed

- An unreadable saved-profile blob is copied to
  `savedTunnels.v2.corrupt-backup` before the store starts from an empty list.
  A corrupt collection used to be indistinguishable from a fresh install, and
  the next save overwrote the only copy of the user's profiles.
- A master now has 30 seconds to publish its control socket instead of 12.
  `ConnectTimeout` bounds only the TCP connect, so a slow network or a large
  agent key set could be reported as a broken master while it was still
  authenticating.

- Clicking the menu-bar icon while the popover is open now dismisses the
  popover. The click already closed the transient popover on mouse-down, and
  the toggle action on mouse-up used to re-open it immediately, so the icon
  could never dismiss its own menu.
- Quick Add imports `-o ExitOnForwardFailure=yes`. It is a boolean that makes
  ssh exit when a forward cannot be established — it runs nothing and reads
  nothing — and RelayBar already sets it on every connection it launches, so
  rejecting it refused an option the app itself depends on.
- An option that is merely outside the preserved set now reports that it is not
  imported, instead of claiming it can execute commands or read arbitrary
  files. That claim was untrue of every harmless option that simply was not
  listed.
- Back from a directly opened remote file now opens the file's containing
  folder with the file selected, instead of dropping straight out of the
  browser to the launcher.

- The menu-bar icon no longer disappears after a launch. The item is now an
  AppKit `NSStatusItem` the application delegate creates and holds, under the
  explicit autosave name `com.relaybarscion.RelayBarScion.status`, so the app
  can assert
  its own visibility at every launch and discard a saved slot that no attached
  screen can display. `MenuBarExtra` kept its status item private, leaving the
  app no way to recover once the system had persisted the icon as hidden.
- Re-launching a running RelayBar opens the menu and re-asserts the icon
  instead of doing nothing, so an unreachable icon is no longer a dead end.
- The menu-bar item is image-only. It previously drew the word "RelayBar" beside
  the glyph, taking roughly three times the width and making the item the first
  one a crowded or notched menu bar drops.
- Standard editing shortcuts reach text fields in the profile editor and the
  Remote Files window again, through a main menu the app now installs itself.
- A retrying profile now counts down to its next attempt. The row used to
  freeze "Retrying in 30s" for the whole backoff, reading like a stuck UI.
- Finished downloads now land with owner-only permissions (`0600` for files,
  `0700` for folders). The staging directory was created locked down, but
  the payload itself kept whatever permissions sftp left once the transfer
  outlived the last poll.

## [1.3.0] - 2026-07-30

### Added

- A native in-popover setting can register RelayBar to launch when the current
  user logs in while leaving every saved forwarding profile stopped.
- Named group menus can start inactive members, stop active members, or restart
  only the members that were active when the command began.
- Image and Markdown previews retain the current folder's previewable files in
  a resizable, hideable sidebar with fast mouse and keyboard switching.

### Changed

- Remote Files reuses one private SSH master for folder listings, previews, and
  downloads. Bounded session caching makes Back and revisits immediate while
  stale folders revalidate without blanking their contents.
- Folder opens now show their target path immediately, remain cancellable, and
  preserve the prior folder and selection when an uncached open fails.
- Image previews use a quieter adaptive canvas, and Markdown uses a focused
  reading width with a calmer toolbar and grow-only preview window sizing.

### Fixed

- Remote Files control sockets account for OpenSSH's temporary bind suffix and
  stay within macOS's Unix-socket path limit.
- Superseded navigation and preview work can no longer publish stale content or
  leave its temporary preview directory behind.
- Login-item failures preserve the system-reported state, and the forwarding
  rule type control no longer squeezes its redundant label into a narrow
  column.

### Security

- The universal stable ZIP is signed with a timestamped hardened-runtime
  Developer ID, notarized by Apple, and stapled for offline Gatekeeper
  verification.
- Remote Files owns and removes its private SSH control socket and continues to
  run bounded, separately cancellable SFTP children without adding a new
  network protocol dependency.

## [1.3.0-beta.1] - 2026-07-26

### Added

- A native in-popover Settings screen can register RelayBar to launch when the
  current user logs in, while leaving every saved forwarding profile stopped.
- Named group menus can start inactive members, stop active members, or restart
  only the members that were active when the command began.

### Fixed

- Login-item operation errors preserve the system-reported toggle state so a
  failed change remains truthful and retryable.
- The forwarding-rule type segmented control no longer squeezes its redundant
  **Type** label into a vertical column at the 380-point popover width.

### Security

- The universal beta ZIP is signed with a Developer ID, notarized by Apple, and
  stapled for offline Gatekeeper verification.

## [1.2.1] - 2026-07-26

### Added

- Remote Files can save a standalone SSH host without creating or starting a
  port-forwarding profile.
- The server picker combines recent successful connections, saved hosts,
  forwarding profiles, and concrete aliases from `~/.ssh/config`.
- Standalone hosts can be removed without changing forwarding profiles or SSH
  config.

### Fixed

- The New Profile form now stays inside the 380-point menu width and no longer
  clips its left edge.
- The Group field displays one label instead of repeating the native picker
  label.

### Security

- SSH-config discovery is read-only and bounded to 1 MiB and 256 concrete host
  aliases. Wildcard, character-pattern, and negated aliases are ignored.
- The universal macOS ZIP is signed with a Developer ID, notarized by Apple,
  and stapled for offline Gatekeeper verification.

## [1.2.0] - 2026-07-25

### Added

- Flexible forwarding profiles with repeated and mixed `-L`, `-D`, and `-R` rules over one managed SSH connection.
- Local and remote SOCKS forwarding, TCP and Unix-socket endpoints, reverse-SOCKS destination policy, and OpenSSH-assigned remote ports.
- Optional profile groups with lightweight sections, move, rename, and ungroup actions that do not restart active SSH processes.
- Exact-path Remote Files browsing with navigation, refresh, file and folder downloads, progress, cancellation, and Finder reveal.
- Safe read-only previews for supported remote images and Markdown, including GFM, common Obsidian reading syntax, syntax highlighting, footnotes, callouts, and native math.

### Changed

- Existing single local-forward records migrate to typed one-rule profiles while preserving stable profile data.
- Quick Add imports forwarding-only SSH commands into validated typed rules without invoking a shell.
- Runtime forwarding state, retry behavior, browser actions, socket cleanup, and Remote Files connection reuse operate on the generalized profile model.
- Post-beta reliability work hardens SSH control buffering, restart coordination, directory progress polling, grouping, and error normalization.

### Security

- Forwarding, Remote Files, and preview inputs use bounded structured parsing and fixed executable argument arrays.
- Remote Markdown remains inert: raw HTML is not activated, remote embeds are not fetched, and unsafe links are blocked.
- SFTP cancellation owns child reaping and serializes signal delivery so delayed escalation cannot target a recycled PID.
- Early child exits cannot terminate RelayBar with `SIGPIPE`, and close-by-default spawning preserves batch standard input.
- The universal macOS ZIP is signed with a Developer ID, notarized by Apple, and stapled for offline Gatekeeper verification.

## [1.2.0-beta.1] - 2026-07-24

### Added

- Flexible forwarding profiles with repeated and mixed `-L`, `-D`, and `-R` rules over one managed SSH connection.
- Local and remote SOCKS forwarding, TCP and Unix-socket endpoints, reverse-SOCKS destination policy, and OpenSSH-assigned remote ports.
- Optional profile groups with lightweight sections, move, rename, and ungroup actions that do not restart active SSH processes.
- Exact-path Remote Files browsing through saved SSH connections, including navigation, refresh, file and folder downloads, progress, cancellation, and Finder reveal.
- Safe read-only previews for supported remote images and Markdown, including GFM, common Obsidian reading syntax, syntax highlighting, footnotes, callouts, and native math.

### Changed

- Existing single local-forward records migrate to typed one-rule profiles while preserving stable profile data.
- Quick Add now imports forwarding-only SSH commands into validated typed rules without invoking a shell.
- Runtime forwarding state, retry behavior, browser actions, socket cleanup, and Remote Files connection reuse now operate on the generalized profile model.
- The menu-bar list, editor, README, GitHub Pages site, and product screenshots now reflect profiles and grouping.

### Security

- Forwarding, Remote Files, and preview inputs use bounded structured parsing and fixed executable argument arrays.
- Remote Markdown remains inert: raw HTML is not activated, remote embeds are not fetched, and unsafe links are blocked.
- Release builds retain the hardened runtime, Developer ID signing, notarization, and Gatekeeper verification workflow.

[1.3.0]: https://github.com/lx2026/RelayBar/releases/tag/v1.3.0
[1.3.0-beta.1]: https://github.com/lx2026/RelayBar/releases/tag/v1.3.0-beta.1
[1.2.1]: https://github.com/lx2026/RelayBar/releases/tag/v1.2.1
[1.2.0]: https://github.com/lx2026/RelayBar/releases/tag/v1.2.0
[1.2.0-beta.1]: https://github.com/lx2026/RelayBar/releases/tag/v1.2.0-beta.1
