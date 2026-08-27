# Task 039 — RelayBar 1.5.1 Release Verification

Verified: 2026-08-27

Result: Pass. The official stable GitHub release, GitHub Pages site, signed
Sparkle appcast, and public Homebrew cask identify 1.5.1. The final notarized
app is installed and running, main CI passes, and issues 28 and 29 are closed.

## Source and automated checks

- Release commit `76128b3fd97233165e5f84221acd0210a393b239` is pushed on
  `codex/fix-homebrew-lifecycle-and-group-controls`; annotated tag `v1.5.1`
  resolves to that commit.
- The warnings-as-errors suite passes 274 tests with 17 expected opt-in skips
  and no failures. Eight Task 038 group-control snapshots pass and were
  inspected in stopped, active, mixed, and long-name states in Aqua and Dark
  Aqua.
- The refreshed release page passes desktop 1440 × 900 and mobile 390 × 844
  browser checks with no horizontal overflow, console warning, or console
  error. Its hero screenshot shows the trailing group controls and its two
  download links target the 1.5.1 asset.
- Release metadata, shell syntax, resource pruning, licenses, matching dSYM
  UUIDs, and `git diff --check` pass.

## Signed public artifact

- Apple accepted notarization submission
  `4d6d7706-ff5e-4680-b050-129ae6701910`; stapling and validation pass.
- `RelayBar.zip` is 6,764,235 bytes with SHA-256
  `e10c1e5e1210e75312901445fc0cb573666ad2aea71f96e8f281f5c824994069`.
- The archive contains RelayBar 1.5.1 build 10, bundle identifier
  `com.lx2026.RelayBar`, macOS 13 minimum, and `x86_64` plus `arm64` slices.
  Strict nested code-signature verification, stapler validation, and
  Gatekeeper assessment pass as `Notarized Developer ID`; the timestamped
  hardened-runtime signature belongs to team `39HYFR5Z65`.
- The non-draft, non-prerelease GitHub release contains one `RelayBar.zip`.
  An anonymous download is byte-identical to the local verified artifact and
  independently passes metadata, architecture, signature, ticket, and
  Gatekeeper checks.
- The production appcast contains three valid signed enclosures. Its new 1.5.1
  enclosure identifies build 10, the public immutable URL, length 6,764,235,
  and a verified EdDSA signature.

## Homebrew and installed application

- Tap commit `7fdaf4e1ce5ec585087e1fbc856602ed0b4e5335` is pushed on
  `codex/fix-relaybar-upgrade-lifecycle`. The cask pins version 1.5.1 and the
  public archive checksum while retaining exactly
  `uninstall quit: "com.lx2026.RelayBar"`.
- Ruby syntax, `brew style --cask`, and `brew livecheck` pass; livecheck reports
  1.5.1 as current. The full Homebrew audit remains blocked because Homebrew on
  this macOS 27 host requires Xcode 27 while Xcode 26.6 is installed.
- In a real running 1.5.0-to-1.5.1 upgrade from a receipt containing the quit
  directive, PID 16283 exits and exactly one build-10 process reopens as PID
  16549. In the stopped path, Homebrew installs build 10 without launching it.
- Preferences remain at SHA-256
  `148aa35a292d86c5d8ee58a2b296e56aca56bf31e442c63a536c5f72b86b8798`.
  Application Support remains 276 files with aggregate manifest SHA-256
  `7d1d72cb90c4009d85611c486b8edb1639a39930f64ce02ca8855d13d9c81d7a`.
- The public cask artifact is installed at `/Applications/RelayBar.app` as
  1.5.1 build 10 and is running as PID 17752. Its signature, stapled ticket,
  and Gatekeeper assessment pass. The displaced 1.5.0 review copy was moved to
  `~/.Trash/RelayBar-pre-1.5.1-review.app` for recoverability.

## Public channel verification

- RelayBar `main` and the release feature branch both resolve to `1ff3603`;
  Homebrew tap `main` and its release feature branch both resolve to `7fdaf4e`.
- GitHub Pages deployment run `33088178321` succeeds from `1ff3603`. The live
  page and live appcast return 1.5.1, and the public tap returns version 1.5.1,
  the verified archive checksum, and the exact quit directive.
- Main CI run `33088179453` passes its Swift package tests and unsigned macOS
  project build.
- GitHub issues 28 and 29 are closed as completed with comments linking the
  official release and the issue-specific verification evidence.
