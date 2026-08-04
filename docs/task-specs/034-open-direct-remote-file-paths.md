# Task 034 — Open Direct Remote File Paths

Status: In Progress

Created: 2026-08-03

## Outcome

Remote Files opens an absolute path that identifies a supported remote file in
its existing preview instead of treating the file as a directory and failing.
The correction ships as RelayBar 1.4.0 Beta 2, build 8.

## Delivery Boundary

- Preserve the exact-path, read-only, shell-free SFTP boundary; do not search,
  index, mount, or edit the remote filesystem.
- Direct image and Markdown paths use the existing bounded previews. Other
  regular files remain visible and selected so the existing download action is
  available without starting a download automatically.
- The maintainer has approved committing, notarizing, publishing, and testing
  Beta 2 and its signed appcast. Stable website and Homebrew publication remain
  outside this beta.

## Work

- Distinguish a requested file from directory contents using the same quoted
  SFTP listing operation, without adding a remote shell command.
- Open a previewable direct file immediately while retaining a coherent Back
  path; present a non-previewable direct file as the selected browser item.
- Preserve cancellation, retry, connection reuse, path validation, preview
  limits, and ordinary directory navigation.
- Publish the signed, notarized universal build 8 archive and signed appcast,
  then exercise the public Beta 1-to-Beta 2 update from an application stored
  in an `/Applications` subdirectory.

## Acceptance

- A direct absolute path to a Markdown or supported image opens the existing
  preview with the exact file selected; Back returns through the single-file
  browser context to the launcher.
- A direct path to another regular file shows that exact file selected without
  a directory error or unsolicited download, while a directory path retains
  existing behavior.
- Parser, model, retry, preview, and complete automated checks pass, including
  `git diff --check` and the warnings-as-errors universal Release build.
- Apple accepts the build 8 notarization; the public Beta 2 ZIP and appcast are
  signed, byte-matched, and independently verified.
- An installed public Beta 1 in an `/Applications` subdirectory discovers,
  installs, and relaunches Beta 2 in place through the public feed, after which
  the supplied `TRANSCRIPTION_LEARNINGS.md` path opens successfully.
