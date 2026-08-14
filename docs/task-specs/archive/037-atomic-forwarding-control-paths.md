# Task 037 — Atomic Forwarding Control Paths

Status: Complete

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

## Evidence

- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31847098674)
  passed the full test suite, warnings-as-errors checks, and unsigned Release
  build for the final implementation commit on 2026-08-14.
- The [follow-up GLM 5.3 review](https://github.com/L-K-M/RelayBar/actions/runs/31847097079)
  completed successfully with no actionable suggestion. Its boundary-coverage
  question was verified against the shared-helper tests for the exact budget
  and first byte over, plus the forwarding-owner residue regression.
- Source review confirmed that both forwarding and Remote Files SSH masters use
  `SSHControlPath.create` and validate cleanup ownership. `git diff --check
  origin/main...HEAD` passed on 2026-08-14. Swift and Xcode were unavailable on
  the Linux workspace, so macOS CI is the build and test authority.
