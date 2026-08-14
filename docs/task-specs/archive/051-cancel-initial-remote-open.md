# Task 051 — Cancel Initial Remote Files Open

Status: Complete

Created: 2026-08-14

## Outcome

Give users an immediate, visible escape from an initial Remote Files open that
may otherwise wait up to 120 seconds for SSH readiness.

## Delivery Boundary

- Reuse the existing cancellable load and SSH-session lifecycle.
- Preserve the entered path and selected server for a later retry.
- Do not change folder-navigation, preview, or transfer cancellation.

## Work

- Keep explicit progress text visible during the initial open.
- Add a native Cancel action with the standard cancel keyboard shortcut.
- Cancel the model task, invalidate delayed completion, and retire the owned SSH
  session without publishing an error or a recent connection.
- Disable launcher inputs while their in-flight values are being opened.
- Add model-level cancellation coverage and update the Remote Files contract.

## Acceptance

- A pending initial open visibly offers Cancel and responds to the standard
  cancel keyboard action.
- Cancel returns the launcher to an idle state without waiting for the SSH
  readiness timeout.
- Entered path and server selection survive cancellation.
- A cancelled completion cannot navigate, report an error, or record a recent.
- A new Open after cancellation starts cleanly and can succeed.
- The service shutdown path runs so owned SSH/SFTP processes are retired.
- Relevant automated checks and `git diff --check` pass.

## Evidence

- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31847032476)
  passed the test suite, warnings-as-errors checks, and unsigned Release build
  for the final implementation commit on 2026-08-14.
- The [initial GLM 5.3 review](https://github.com/L-K-M/RelayBar/actions/runs/31846489049)
  completed and its useful late-completion concern was addressed with a
  deliberately non-cooperative deferred-load fixture. The final test forces a
  cancelled generation to fail late, verifies no error, navigation, or recent,
  and then verifies a fresh Open succeeds.
- The [follow-up GLM run](https://github.com/L-K-M/RelayBar/actions/runs/31847031189)
  could not produce a review because all three API attempts returned HTTP 429;
  this is recorded as an external review-service limit, not a code failure.
- Source review confirmed every initial-open success and failure publication is
  generation-guarded and cancellation invokes service shutdown. `git diff
  --check origin/main...HEAD` passed on 2026-08-14. Swift and Xcode were
  unavailable on the Linux workspace, so macOS CI is the build authority.
