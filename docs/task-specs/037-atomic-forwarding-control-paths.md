# Task 037 — Atomic Forwarding Control Paths

Status: In Progress

## Outcome

Forwarding-profile and Remote Files SSH masters use the same atomically created,
private control-path boundary and reserve the complete path space OpenSSH needs.

## Delivery Boundary

Keep one private multiplexing master per existing owner. Do not change process
lifecycle, forwarding semantics, retry policy, or user-selected local Unix socket
handling.

## Work

- Replace forwarding's check/remove/create sequence with `mkdtemp` ownership.
- Share the short directory prefix, socket name, Darwin path capacity, OpenSSH
  temporary suffix, and cleanup rules with Remote Files.
- Make the forwarding temporary root injectable for deterministic boundary tests.
- Document the implemented process boundary.

## Acceptance

- The longest supported final socket path succeeds and the first byte over the
  OpenSSH budget fails without leaving a directory.
- Concurrent creation returns only unique `0700` directories.
- Both SSH master owners use the shared primitive and validate cleanup ownership.
- Relevant tests and the warnings-as-errors build pass.
- `git diff --check` passes.
