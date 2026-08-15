# Changelog

Notable RelayBar changes are recorded here.

## [Unreleased]

### Added

- Profiles can be duplicated from the row menu. The copy gets fresh profile
  and rule identities, lands right after the original, and starts stopped —
  clone-then-tweak without retyping a connection.
- Profiles can be marked **Start at Launch** in the editor or row menu, and
  RelayBar starts those profiles automatically when it launches.
- Row menus can copy a profile as the `ssh` command RelayBar effectively
  runs — same grammar Quick Add imports, so the command pastes straight back
  or into a terminal.

### Fixed

- Quick Add imports `-o ExitOnForwardFailure=yes`. It is a boolean that makes
  ssh exit when a forward cannot be established — it runs nothing and reads
  nothing — and RelayBar already sets it on every connection it launches, so
  rejecting it refused an option the app itself depends on.
- An option that is merely outside the preserved set now reports that it is not
  imported, instead of claiming it can execute commands or read arbitrary
  files. That claim was untrue of every harmless option that simply was not
  listed.

- The menu-bar icon no longer disappears after a launch. The item is now an
  AppKit `NSStatusItem` the application delegate creates and holds, under the
  explicit autosave name `com.lx2026.RelayBar.status`, so RelayBar can assert
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
