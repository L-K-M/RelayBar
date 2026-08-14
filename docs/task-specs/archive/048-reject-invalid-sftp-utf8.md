# Task 048 — Reject Invalid SFTP UTF-8

Status: Complete

## Outcome

Remote Files rejects a successful SFTP listing whose standard output is not
valid UTF-8 instead of presenting it as an empty folder.

## Delivery Boundary

- Keep the existing SFTP process, temporary-file, and byte-limit boundaries.
- Require lossless UTF-8 only for successful listing output that RelayBar
  parses as remote metadata.
- Keep failed-command diagnostics bounded and loss-tolerant so malformed bytes
  do not erase otherwise actionable error text.

## Work

- Preserve whether captured standard output decoded losslessly.
- Reject a successful listing with a distinct typed error when opening its
  captured standard output for reading fails.
- Surface invalid successful listing output as a typed user-facing error.
- Decode bounded standard error with replacement characters before existing
  diagnostic normalization.
- Confirm each capture limit with a one-byte post-cap probe before interpreting
  UTF-8 so truncation cannot be mistaken for an encoding failure.
- Cover invalid listing bytes, actionable malformed diagnostics, and the
  diagnostic byte limit.

## Acceptance

- A zero-status SFTP listing containing invalid UTF-8 throws the typed encoding
  error and never returns an empty entry collection.
- Unreadable successful listing output also cannot masquerade as an empty
  folder, while readable zero-byte output remains a valid empty folder.
- A failed SFTP command with malformed diagnostic bytes still maps recognizable
  bounded text to the existing friendly error.
- Oversized malformed diagnostics still fail with the existing response-size
  error.
- Either capture cap fails closed even when sftp exits successfully.
- Relevant tests and `git diff --check` pass, and the Remote Files and shared
  security specifications describe the implemented boundary.

## Evidence

- macOS 15 CI ran `swift test -Xswiftc -warnings-as-errors`: 260 tests passed
  with 15 skipped and no failures on 2026-08-14.
- The same CI run completed the unsigned RelayBar Release build with
  `xcodebuild` on 2026-08-14.
- Fixture syntax, raw invalid-byte assertions, unreadable-capture permissions,
  task-number references, and `git diff --check` passed locally on 2026-08-14.
- GLM 5.3 completed with zero actionable suggestions after the final
  implementation review on 2026-08-14.
