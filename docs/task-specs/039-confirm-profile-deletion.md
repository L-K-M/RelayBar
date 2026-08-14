# Task 039 — Confirm Profile Deletion

Status: In Progress

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
- Confirming **Delete Profile** invokes the existing deletion path exactly once.
- The confirmation identifies the profile and route, and active lifecycle
  phases include the connection-stopping warning.
- Relevant automated checks and `git diff --check` pass.
