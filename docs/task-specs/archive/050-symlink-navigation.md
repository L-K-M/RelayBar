# Task 050 — Navigate Symbolic Links in Remote Files

Status: Complete

Created: 2026-08-14

## Outcome

A symbolic link in Remote Files behaves like what it points at: activating
a link to a directory navigates through it, a link to a Markdown or image
file previews it, and a link to any other file downloads it — instead of
double-clicking a linked folder failing with a download error.

## Delivery Boundary

- No shell and no new command shape: the directory probe is the existing
  quoted `ls -la` with a trailing slash, which the remote side resolves
  through the link. A link to a file (or a dangling link) fails that probe
  and falls back to file treatment.
- Preview and download keep following the link server-side; the link's own
  size (the target-path length) is never treated as the file's size, so
  downloads of linked files show indeterminate progress and previews use
  the existing bounded limits.
- Ordinary directories, files, and the exact-path, read-only boundary are
  unchanged.

## Work

- Add `listSymlinkTarget` to the serving protocol (default: unsupported),
  implemented by SFTP with the trailing-slash listing, and by the test stub.
- Route `activate` for `.symbolicLink` through the probe with the
  directory-commit and file-fallback paths in the model.
- Add model tests for link-to-directory and link-to-Markdown; update the
  remote-files system spec.

## Acceptance

- Activating a link to a directory lists the linked folder, keeps Back
  history, and uses the link path as the current path.
- Activating a link to a Markdown file previews it; other linked files
  download without claiming the link's own size as the file's size.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `SFTPRemoteFileService.listSymlinkTarget` issues `ls -la "<path>/"` and
  parses with the link path as the parent, so entries hang under the link
  and navigation continues through it.
- `RemoteFilesModel.openSymbolicLink` reuses the load-task/generation
  discipline, commits through `commitLoadedFolder` (history push), and on
  failure reclassifies the entry as a file with `size: nil` before preview
  or download.
- Two model tests cover the directory navigation and the Markdown preview
  fallback through the stub's `listSymlinkTarget`.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
