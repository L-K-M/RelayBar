# Changelog

Notable RelayBar changes are recorded here.

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

[1.2.0-beta.1]: https://github.com/lx2026/RelayBar/releases/tag/v1.2.0-beta.1
