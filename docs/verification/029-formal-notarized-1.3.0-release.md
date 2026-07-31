# Task 029 — Formal Notarized 1.3.0 Release Verification

Verified: 2026-07-30

Result: Pass. RelayBar 1.3.0 is the public stable GitHub release, its
independently verified archive is installed by the public Homebrew cask, and
the project website presents the same version.

## Release identity

| Item | Evidence |
|---|---|
| Release | [RelayBar 1.3.0](https://github.com/lx2026/RelayBar/releases/tag/v1.3.0), stable and not a prerelease |
| Release commit | `cfb6dea410c7efd5f4c82029e0315d916ab3c2c3` |
| Tag | Annotated `v1.3.0`, resolving to the release commit |
| App metadata | Version 1.3.0, build 6, `com.lx2026.RelayBar`, macOS 13 minimum |
| Archive | `RelayBar.zip`, 5,389,681 bytes |
| SHA-256 | `127670e8e5afa51e92ea65c51ca3f56144f85b7f54bda218d517b3dd4f17aa7a` |
| Architectures | `x86_64 arm64` |
| Signing identity | `Developer ID Application: Thought Tides LLC (39HYFR5Z65)` |
| Notarization | Accepted submission `f5ca8dc8-6f10-4100-b0a5-fd09af9e5167`, zero issues |
| Gatekeeper | Accepted, `source=Notarized Developer ID` |
| Executable/dSYM UUIDs | `226E8E5C-852F-37BD-B899-59A48721E49E`; `D7B8A2C0-6D73-3C8C-8299-7165657A6B8B` |

## Automated and build checks

- The first full test run exposed a test-only data race on macOS 27: concurrent
  superseding folder loads appended to `StubRemoteFileService.listRequests`
  without synchronization, and XCTest exited with `SIGSEGV`. The stub's shared
  state is now lock-protected. The isolated regression passed, followed by the
  complete `swift test -j 1 --no-parallel -Xswiftc -warnings-as-errors` run:
  205 tests passed with 15 expected opt-in skips and no failures.
- The warnings-as-errors universal Xcode Release build passed for `arm64` and
  `x86_64`. `Packaging/Info.plist`, version consistency, local website assets,
  bundled notices, and `git diff --check` passed.
- [GitHub Actions run 30601660334](https://github.com/lx2026/RelayBar/actions/runs/30601660334)
  passed against the tagged release commit.
- The opt-in live Remote Files test listed `/` through the app-owned SSH
  session against `spark-422e.local` in 5.85 seconds.

## Artifact verification

- `./scripts/notarize-release.sh` built and signed the archive from a clean
  release commit. Apple accepted it, and the script stapled and validated the
  app before rebuilding the final ZIP.
- `codesign --verify --deep --strict`, `xcrun stapler validate`, and
  `spctl --assess --type execute --verbose=4` passed on the final app, a clean
  local extraction, and an independently downloaded and quarantined public
  extraction.
- The GitHub asset reports the same SHA-256 as the final local ZIP. A fresh
  unauthenticated download was byte-for-byte identical, and no asset was
  replaced after verification.
- The executable contains both required slices and matches both dSYM UUIDs.
  The hardened-runtime signature is timestamped.
- The final bundle contains `THIRD_PARTY_NOTICES.txt`, Highlighter's formatter
  plus only `github.css` and `github-dark.css`, and SwiftMath's selected Latin
  Modern font, metrics, and three font-license files. The package-development
  conversion script and unused renderer resources are absent.
- The clean extracted app remained running during a two-second launch smoke.
  The user's existing installed RelayBar process was not disturbed by that
  check.

## Public documentation

- At publication, `main` pointed to the release commit. The annotated tag and
  stable release continue to identify that exact commit and its sole
  application archive.
- The README download and every project-site release link point to 1.3.0.
- [GitHub Pages run 30601659949](https://github.com/lx2026/RelayBar/actions/runs/30601659949)
  deployed commit `cfb6dea410c7efd5f4c82029e0315d916ab3c2c3`.
- The public [RelayBar website](https://lx2026.github.io/RelayBar/) was
  inspected at 1440 × 900 and 390 × 844. Both layouts showed the 1.3.0 badge,
  release copy, and download URL with no horizontal overflow.

## Homebrew

- Public tap commit
  [`195d62c0d951e53f5b332eba0c3e36876dc115c2`](https://github.com/lx2026/homebrew-tap/commit/195d62c0d951e53f5b332eba0c3e36876dc115c2)
  updates `relaybar` to 1.3.0 and the exact final archive SHA-256.
- Homebrew 6.0.13 style inspected the cask with no offenses. Livecheck
  resolved 1.3.0 to 1.3.0. The current strict online and signing
  `Cask::Auditor` downloaded the public archive and returned zero findings.
- The top-level `brew audit` wrapper remains unavailable on this machine
  because Homebrew requires Xcode and Command Line Tools 27 while the machine
  has Xcode 26.6 and Command Line Tools 26.3. Calling the same current auditor
  through `brew ruby` bypassed only that host-toolchain preflight.
- A real `brew upgrade --cask lx2026/tap/relaybar` upgraded the recorded 1.2.1
  receipt to 1.3.0. The installed app reported build 6, matched the release app
  bytes, passed signature, ticket, and Gatekeeper checks, and launched.
- Uninstall removed the managed application while leaving the RelayBar
  preferences file byte-identical and all 91 existing application-support
  entries present. A clean cask install then restored the same verified app
  and launched it successfully.

## Environment boundary

- Local release and Homebrew verification ran on Apple Silicon macOS 27.0.
  The `x86_64` slice and macOS 13 deployment target were structurally verified
  by the universal build, metadata, and dSYM checks but were not executed on an
  Intel Mac or macOS 13 host.
- Deterministic forwarding integration tests passed, and the accepted
  pre-release task evidence already covers native forwarding interactions.
  This release pass added a live Remote Files transport check but did not
  repeat the optional live forwarding-server matrix.
- No official `homebrew/cask` pull request or update framework publication was
  performed.
