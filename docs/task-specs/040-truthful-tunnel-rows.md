# Task 040 — Truthful and Inspectable Tunnel Rows

Status: In Progress

Created: 2026-08-14

## Outcome

Make compact tunnel rows accurately describe retry and browser behavior while
keeping truncated values and row actions discoverable.

## Delivery Boundary

- Keep the current row density, lifecycle model, and retry schedule.
- Do not add a ticking countdown or store-wide timer.
- Continue opening URLs through the user's macOS default browser.

## Work

- Replace the static-delay countdown claim with truthful waiting copy.
- Replace Safari-specific symbols and wording with default-browser affordances.
- Add native full-value help to truncated row strings.
- Give each row actions menu stable profile-specific accessibility text.
- Add deterministic copy tests and update the affected system contracts.

## Acceptance

- Retrying rows never claim a remaining duration they do not calculate.
- Default-browser actions contain no Safari-specific symbol or label.
- The complete profile name, route, and status value are available on hover.
- The browser button and actions menu have stable accessibility names.
- Relevant automated checks and `git diff --check` pass.
