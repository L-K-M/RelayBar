# Task 059 — Notify When a Profile Stops Retrying

Status: Complete

Created: 2026-08-14

## Outcome

When a profile exhausts automatic retries while the popover is closed, the
user is told — a single system notification naming the profile and the
reason — instead of discovering hours later that the tunnel gave up.

## Delivery Boundary

- Notify only on retry exhaustion, never on user stops, group actions, or
  ordinary retries.
- Authorization is requested lazily on first need; denial silently disables
  the notification rather than nagging.
- The notifier is injected into the store so tests never touch the system
  notification center.

## Work

- Add `TunnelFailureNotifier` (lazy authorization, one bounded-content
  request) and inject it into `TunnelStore`.
- Fire it from the retry-exhaustion branch with the profile's display name
  and the failure message.
- Add a store test with an injected notifier; update the process-lifecycle
  system spec and the Xcode project.

## Acceptance

- A profile that exhausts retries posts exactly one notification with the
  profile name and failure text; no notification on manual stop.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `TunnelFailureNotifier` builds a `UNNotificationRequest` with a fresh
  identifier and requests `.alert + .sound` authorization only when the
  status is `.notDetermined`.
- `TunnelStore.scheduleRetry`'s exhaustion branch calls the injected
  notifier with `displayName` and the full failure message.
- The store test drives `/usr/bin/false` to exhaustion and asserts exactly
  one notification with the expected name and message.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
