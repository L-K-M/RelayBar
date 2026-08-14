# Task 038 — Reject Invalid SFTP UTF-8

Status: In Progress

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
- Reject a successful listing when its captured standard output cannot be read.
- Surface invalid successful listing output as a typed user-facing error.
- Decode bounded standard error with replacement characters before existing
  diagnostic normalization.
- Cover invalid listing bytes, actionable malformed diagnostics, and the
  diagnostic byte limit.

## Acceptance

- A zero-status SFTP listing containing invalid UTF-8 throws the typed encoding
  error and never returns an empty entry collection.
- Unreadable successful listing output also cannot masquerade as an empty
  folder.
- A failed SFTP command with malformed diagnostic bytes still maps recognizable
  bounded text to the existing friendly error.
- Oversized malformed diagnostics still fail with the existing response-size
  error.
- Relevant tests and `git diff --check` pass, and the Remote Files and shared
  security specifications describe the implemented boundary.
