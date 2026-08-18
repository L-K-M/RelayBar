# Task 034 — Open Direct Remote File Paths Verification

Verified: 2026-08-18

Result: Pass. Direct remote-file paths use the existing bounded preview or
selection flow, and the tested build 8 artifact is the public RelayBar 1.4.0
stable release.

## Behavior and live transport

- Parser, model, launcher, browser-state, retry, cancellation, image-preview,
  Markdown-preview, and service tests cover direct previewable files, other
  regular files, directories, invalid paths, and coherent Back navigation.
- The complete warnings-as-errors suite passed 234 tests with 14 expected
  opt-in skips and no failures while the live direct-file check was enabled.
- The live check connected as `linxy97@spark-422e.local` through the designated
  Tailscale identity and opened
  `/home/linxy97/workspace/2026/youtube-video-transcript/TRANSCRIPTION_LEARNINGS.md`.
  It verified exact remote metadata, bounded transfer, and nonempty Markdown
  decoding without adding a remote shell command.
- The warnings-as-errors universal Release build and `git diff --check` passed.
  The implemented behavior is recorded in
  [`remote-files.md`](../system-specs/modules/remote-files.md).

## Build 8 and updater

- Apple accepted Beta 2 notarization submission
  `d2157c19-02ff-4195-945a-9f5b3a074c22`. The stapled universal archive is
  RelayBar 1.4.0 build 8 and passed strict nested signature, Gatekeeper,
  architecture, minimum-system, and executable/dSYM UUID verification.
- A real public Beta 1 installed below `/Applications` discovered, installed,
  and relaunched build 8 in place through the signed public appcast. The
  maintainer confirmed the update succeeded.
- The tested Beta 2 archive was promoted byte-for-byte as the stable
  [`v1.4.0` release](https://github.com/lx2026/RelayBar/releases/tag/v1.4.0):
  6,538,729 bytes, SHA-256
  `292ccadee9e8577c65cac86592778501c51591990a803685c0b71db004e4d105`.
  An anonymous stable download was identical and passed the same verification.
- The public appcast byte-matches the repository feed, verifies its signature,
  and encloses the stable ZIP with the tested EdDSA signature. Pages deployment
  [32170121350](https://github.com/lx2026/RelayBar/actions/runs/32170121350)
  published the feed after [PR 22](https://github.com/lx2026/RelayBar/pull/22)
  passed CI and merged.
