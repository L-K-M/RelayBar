# Task 023 — Homebrew Cask Verification

Verified: 2026-07-30

## Published boundary

- The public `lx2026/homebrew-tap` repository contains
  `Casks/relaybar.rb` and documents
  `brew install --cask lx2026/tap/relaybar`.
- The cask declares RelayBar 1.2.1, macOS Ventura or newer, the canonical
  homepage, and only `app "RelayBar.app"`.
- It contains no postflight, installer, `zap`, quarantine bypass, credential,
  local path, notarization profile, or `auto_updates` stanza.
- The official `homebrew/cask` submission remains deferred.

## Release identity

The archive cached from the cask URL was inspected independently:

| Check | Evidence |
|---|---|
| Archive SHA-256 | `71ea4cfd18a703e9dbcd5085c2b6b387dcd82635f9dbd99bae07a11adf51a3b8`, identical to the cask |
| App version | `CFBundleShortVersionString` 1.2.1; build 4 |
| Architectures | `x86_64 arm64` |
| Code signature | `codesign --verify --deep --strict` passed |
| Gatekeeper | accepted, source `Notarized Developer ID` |
| Stapled ticket | `xcrun stapler validate` passed |

The local Homebrew receipt records a requested installation of cask 1.2.1 on
2026-07-26. The cask uses Homebrew's standard `app` artifact, so uninstall
removes the managed application and has no instruction capable of removing
RelayBar preferences or other user data.

The currently installed `/Applications/RelayBar.app` was later replaced by a
manually deployed 1.3.0 test build. It was deliberately not removed or
reinstalled during this verification pass.

## Homebrew checks

- `brew style lx2026/tap/relaybar` inspected one file with no offenses.
- Homebrew's current strict online and signing `Cask::Auditor` completed
  without findings and used the exact cached archive above.
- The top-level `brew audit` wrapper could not run on this Mac because the
  current Homebrew preflight now requires Xcode and Command Line Tools 27 while
  the machine has 26.6. Invoking the same current auditor directly through
  `brew ruby` bypassed only that host-toolchain preflight, not any cask audit.

## Documentation

- The project README distinguishes Homebrew installation and upgrade from the
  direct stable download.
- The static project website shows the tested Homebrew installation command
  beside the direct notarized download.
- The build-and-release system spec defines cask version, checksum, audit,
  install, Gatekeeper, and uninstall maintenance for later stable releases.

## Result

The maintainer tap is live and the cask resolves to the same immutable,
universal, signed, notarized RelayBar 1.2.1 archive as the direct release.
Task 023 is accepted. Closing the public issue records delivery; it does not
authorize submission to the official Homebrew cask repository.
