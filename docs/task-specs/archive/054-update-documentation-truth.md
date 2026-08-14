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
- `git diff --check` passed. Swift and Xcode are unavailable in this Linux
  environment; no updater behavior or executable code path changed.
