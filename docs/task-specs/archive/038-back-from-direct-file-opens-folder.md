# Task 038 — Back From a Direct File Opens the Containing Folder

Status: Complete

Created: 2026-08-14

Follows: Task 034

## Outcome

Pressing Back in the single-file browser context that a directly opened
remote file creates loads the containing folder with the file selected,
instead of abandoning the browser for the launcher.

## Delivery Boundary

- Preserve the exact-path, read-only boundary: the change only reuses the
  existing directory load with the already-known parent path.
- Preview → browser → containing folder → launcher is the full Back chain;
  every earlier step (close preview, cancel in-flight open, ordinary history
  pop) keeps its current behavior.
- The launcher keeps the last presented path, which is now the folder.

## Work

- Track whether the browser is showing a directly opened file and, when no
  navigation history exists, route Back to a normal folder load of the
  current path with the file selected.
- Update the direct-path model test to the new chain and the remote-files
  system spec.

## Acceptance

- From a directly opened previewable file: Back closes the preview, Back
  opens the containing folder with the file selected, Back reaches the
  launcher.
- Ordinary folder history navigation and Back-to-launcher from an initial
  folder are unchanged.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `RemoteFilesModel.commitLoadedFile` recorded the parent path but pushed no
  history, so `goBack()` found an empty stack and exited to the launcher. A
  `showsDirectFile` flag now routes that Back press to the parent folder load
  with the file as `selectionAfterLoad`.
- The updated `testDirectMarkdownPathOpensPreviewAndPreservesBackPath`
  exercises preview → browser → containing folder (selected file, one list
  request for the parent path) → launcher.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
