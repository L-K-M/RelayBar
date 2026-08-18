# Task 035 — Stabilize Copy Confirmation Test Verification

Updated: 2026-08-03

Result: Complete.

## Incident evidence

- The [failed main run](https://github.com/lx2026/RelayBar/actions/runs/30868670868)
  executed 234 tests with 15 expected skips and one failure:
  `testCopyWritesDisplayTextAndAnnouncesSuccess` still observed the confirmation
  after a fixed 30-millisecond sleep.
- The [successful pull-request run](https://github.com/lx2026/RelayBar/actions/runs/30868664486)
  used tree `8fbc49d121ff8e575cf68223bd1f636699a08a23`, exactly matching the failed
  merge run. This isolates the failure to scheduling-sensitive test behavior,
  not a source difference.
- Independent read-only review confirmed that separate timer wakeups do not
  guarantee main-actor execution order and approved observing the published
  state transition with a cooperative XCTest expectation.

## Implementation evidence

- The test subscribes before `copyVersion()`, skips the initial replayed
  `false`, observes the first later `false`, keeps its cancellable alive, and
  awaits a one-second bounded expectation without blocking the main actor.
- Pasteboard content, accessibility announcement, immediate visible state,
  and eventual reset assertions remain intact. Production confirmation timing
  is unchanged.

## Verification evidence

- The focused `ApplicationAboutTests` suite passed with warnings as errors.
- The exact affected test passed 100 of 100 repeated focused runs.
- A temporary five-second reset delay produced the expected one-second
  `Copy confirmation clears` timeout and failed assertion; the delay was then
  restored to the test-only 10-millisecond value.
- The complete warnings-as-errors suite passed 234 tests with 15 expected
  opt-in skips and zero failures.
- The CI-equivalent unsigned Release Xcode build passed with strict concurrency
  and warnings as errors.
- `Packaging/Info.plist` validation and `git diff --check` passed.
