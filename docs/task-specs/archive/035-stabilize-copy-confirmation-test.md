# Task 035 — Stabilize Copy Confirmation Test

Status: Complete

Created: 2026-08-03

Accepted: 2026-08-03

## Outcome

CI verifies that version-copy confirmation clears without assuming the main
actor will service a short timer within a fixed wall-clock delay.

## Delivery Boundary

- Correct the flaky test, not the shipped 1.5-second confirmation behavior.
- Account for independent timer wakeups re-entering the main actor in an
  order that a loaded runner does not guarantee.
- Keep the assertion event-driven and bounded so a real failure still ends
  promptly and reports the missing state transition.
- Do not weaken or remove the assertions covering pasteboard content,
  accessibility announcement, visible confirmation, or its eventual reset.

## Work

- Replace the fixed post-delay assertion with an observation of the published
  confirmation state and an XCTest expectation.
- Record the CI failure and the identical successful PR-tree run as evidence
  that the defect is test scheduling rather than product behavior.
- Stress the focused test, then run the complete CI-equivalent test and build
  checks with warnings treated as errors.

## Acceptance

- The test observes the `true` to `false` confirmation transition directly and
  fails with a bounded timeout if that transition never occurs.
- Repeated focused runs pass without timing failures.
- The complete warnings-as-errors test suite, unsigned project build, and
  `git diff --check` pass.
- Verification evidence is recorded and this accepted task is archived.
