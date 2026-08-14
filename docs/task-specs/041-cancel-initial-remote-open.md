# Task 041 — Cancel Initial Remote Files Open

Status: In Progress

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
- The service shutdown path runs so owned SSH/SFTP processes are retired.
- Relevant automated checks and `git diff --check` pass.
