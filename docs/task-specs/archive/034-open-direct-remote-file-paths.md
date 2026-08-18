# Task 034 — Open Direct Remote File Paths

Status: Complete

Created: 2026-08-03

Accepted: 2026-08-18

## Outcome

Remote Files opens an absolute path that identifies a supported remote file in
its existing preview instead of treating the file as a directory and failing.
The correction shipped in RelayBar 1.4.0 build 8; the tested Beta 2 artifact
was promoted byte-for-byte as the stable release.

## Delivery Boundary

- Preserve the exact-path, read-only, shell-free SFTP boundary; do not search,
  index, mount, or edit the remote filesystem.
- Direct image and Markdown paths use the existing bounded previews. Other
  regular files remain visible and selected so the existing download action is
  available without starting a download automatically.
- Preserve existing directory behavior, retry, cancellation, connection reuse,
  path validation, and preview limits.

## Work

- Distinguish a requested file from directory contents using the same quoted
  SFTP listing operation, without adding a remote shell command.
- Open a previewable direct file immediately while retaining a coherent Back
  path; present a non-previewable direct file as the selected browser item.
- Publish, notarize, and verify the universal build 8 archive and signed
  appcast, then exercise the public Beta 1-to-build 8 updater path from an
  application stored in an `/Applications` subdirectory.

## Acceptance

- A direct absolute path to a Markdown or supported image opens the existing
  preview with the exact file selected; Back returns through the single-file
  browser context to the launcher.
- A direct path to another regular file shows that exact file selected without
  a directory error or unsolicited download, while a directory path retains
  existing behavior.
- Parser, model, retry, preview, live SFTP, and complete automated checks pass,
  including `git diff --check` and the warnings-as-errors universal Release
  build.
- Apple accepted build 8 notarization. The public ZIP and appcast are signed,
  byte-matched, and independently verified.
- An installed public Beta 1 in an `/Applications` subdirectory discovered,
  installed, and relaunched build 8 in place through the public feed. The exact
  supplied Markdown path passed the live SSH path and bounded preview checks.
