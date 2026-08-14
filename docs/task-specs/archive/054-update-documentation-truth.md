# Task 054 — Align Update UI and Documentation

Status: Complete

Created: 2026-08-14

## Outcome

RelayBar's Settings copy and maintained documentation describe its shipped
update behavior, network contact, and dependencies accurately.

## Delivery Boundary

- Change Settings copy and repository documentation only; do not alter updater
  behavior, feed configuration, release artifacts, or historical evidence.
- Preserve the existing opt-in seven-day cadence and disabled automatic
  download and installation behavior.

## Work

- Name the Settings preference for the scheduled check it actually controls.
- Correct the application-shell spec, security review, privacy policy, active
  task index, and system-spec review date.
- Add Tasks 039 and 042 to the archived-task index, which had not recorded
  their completion.
- Record the pinned Sparkle boundary, update-request privacy behavior, and
  ordinary hosting metadata exposure without claiming that update checks are
  anonymous.

## Acceptance

- Settings says **Automatically Check for Updates** in both visible and
  accessibility-facing copy while retaining its existing explanation.
- Current system, security, and privacy documentation agrees with the shipped
  HTTPS feed, opt-in schedule, empty system-profile allowlist, signed-update
  checks, and disabled automatic download and installation settings.
- The task index lists every active task, maintained-document dates are
  current, relevant static checks pass, and `git diff --check` passes.

## Evidence

- Source and property-list assertions passed on 2026-08-14 for the Settings
  label, HTTPS feed, seven-day cadence, empty system-profile allowlist, signed
  feed and archive requirements, automatic checks off by default, and disabled
  automatic downloads and installations.
- The active-task index names Tasks 032 and 034, which are the two specs still
  marked `In Progress`.
- Tasks 039 and 042 are `Complete` at their indexed archive paths, and the
  active and archive task-index links resolve.
- RelayBar starts Sparkle at launch and resets its cycle after the scheduled
  check preference changes. Pinned Sparkle 2.9.4 may run an overdue scheduled
  check promptly, so the application spec and privacy policy allow for that
  network timing without claiming every enable or launch makes a request.
- `git diff --check` passed. Swift and Xcode are unavailable in this Linux
  environment; the only executable-code changes are the visible and
  accessibility-facing Settings label strings, and no updater behavior or
  logic changed.
