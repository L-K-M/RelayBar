# Task 044 — Lock Down Finished Downloads

Status: Complete

Created: 2026-08-14

## Outcome

A completed Remote Files download lands at its destination with owner-only
permissions — `0600` for a file, `0700` for a folder — instead of whatever
permissions sftp happened to leave when the transfer finished.

## Delivery Boundary

- Only the success path changes: one chmod on the staged payload before it
  is moved or exchanged into place. Failure, cancellation, and staging
  cleanup are untouched.
- The payload root is what gets secured; recursive folder contents keep
  their transferred permissions behind the `0700` root.

## Work

- Re-apply `securePartialPermissions` to the finished payload after the
  transfer completes and the existence/limit checks pass.
- Extend the download test with a `0600` assertion and update the
  remote-files system spec.

## Acceptance

- A downloaded file lands with `0600`; a downloaded folder with `0700`.
- Existing-destination replacement keeps the new payload's permissions.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `securePartialPermissions` previously ran only inside the progress-polling
  loop, whose last pass could precede the transfer's end by up to the poll
  interval; the payload's final permissions were whatever sftp set last.
  The success path now secures the payload once more before the
  move/replace.
- `testFileDownloadMovesACompletePartialIntoPlace` now asserts `0600` on
  the replaced destination.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
