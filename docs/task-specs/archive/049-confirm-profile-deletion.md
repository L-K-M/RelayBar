# Task 049 — Confirm Profile Deletion

Status: Complete

Created: 2026-08-14

## Outcome

Prevent an accidental row-menu action from permanently deleting a saved
forwarding profile or silently stopping its active SSH connection.

## Delivery Boundary

- Keep deletion in the existing row menu and use a native macOS confirmation.
- Do not add undo, profile recovery, or persistence-format changes.
- Preserve the existing confirmed-deletion cleanup behavior.

## Work

- Replace immediate deletion with a destructive confirmation and explicit
  cancel action.
- Identify the selected profile with its display name, forwarding summary, and
  SSH host so similarly named profiles can be distinguished.
- Warn when confirming will stop a starting, retrying, or running connection.
- Cover inactive and active prompt content with deterministic tests.
- Update the tunnel-management system contract.

## Acceptance

- Choosing **Delete\u{2026}** does not mutate the store before confirmation.
- Cancelling dismisses the confirmation without stopping or deleting anything.
- No other profile affordance bypasses the row confirmation.
- Confirming **Delete Profile** invokes the existing deletion path exactly once.
- The confirmation identifies the profile and route, and active lifecycle
  phases include the connection-stopping warning.
- Relevant automated checks and `git diff --check` pass.

## Evidence

- Source inspection confirmed that **Delete\u{2026}** only presents the dialog,
  Cancel has no action, and the destructive confirmation owns the sole
  production call to `TunnelStore.delete`. Prompt tests cover every current
  lifecycle phase and compare the warning directly with `isLifecycleActive`.
- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31846909116)
  passed the warnings-as-errors Swift suite and unsigned Release Xcode build on
  commit `c8fbc9e`.
- The [follow-up GLM run](https://github.com/L-K-M/RelayBar/actions/runs/31846906411)
  exhausted all three Z.ai requests with HTTP 429 and generated no review. The
  earlier actionable feedback was addressed in `c8fbc9e`; this remaining
  result is an external reviewer-availability limitation.
- Static acceptance assertions and `git diff --check` passed on 2026-08-14.
