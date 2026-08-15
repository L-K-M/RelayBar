# Task 040 — Live Retry Countdown

Status: Complete

Created: 2026-08-14

## Outcome

A retrying profile's row counts down the seconds until the next attempt,
replacing the static "Retrying in Xs" text that stayed frozen for the whole
backoff and read like a stuck UI.

## Delivery Boundary

- Keep the retry phase's attempt, maximum, delay, and message semantics and
  the exponential backoff unchanged.
- Tick in the view only; no new per-second store publication or process
  activity.

## Work

- Record the retry deadline in the store when a retry is scheduled; clear it
  on cancel, stop, exhaustion, and when the retry fires.
- Render the row's retrying line with a one-second `TimelineView` against
  the deadline, falling back to the static text when no deadline exists.
- Add a focused store test and update the application-shell system spec.

## Acceptance

- While a profile retries, the row visibly counts down to zero and then the
  profile relaunches through the existing path.
- Stopping a retrying profile clears its deadline.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `TunnelStore.scheduleRetry` stores `retryDeadlines[id]` alongside the
  retrying phase; `cancelRetry`, the exhaustion branch, and the retry task
  itself clear it. The accessor is deliberately not published — the row only
  reads it while the published retrying phase is current.
- `TunnelRow` renders the retrying line inside a one-second `TimelineView`
  computing remaining seconds from the deadline.
- A focused test asserts the deadline is recorded near the injected delay
  and cleared on stop.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
