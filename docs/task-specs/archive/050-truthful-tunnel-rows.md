# Task 050 — Truthful and Inspectable Tunnel Rows

Status: Complete

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

## Evidence

- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31846935015)
  passed the test suite, warnings-as-errors checks, and unsigned Release build
  on 2026-08-14.
- The [follow-up GLM 5.3 review](https://github.com/L-K-M/RelayBar/actions/runs/31846932641)
  completed successfully after the copy assertion was made prefix-specific;
  it produced no remaining actionable finding.
- Source review confirmed that the browser action still routes through
  `NSWorkspace.shared.open`, while the visible symbol and accessibility copy
  are browser-neutral.
- `git diff --check origin/main...HEAD` passed on 2026-08-14. Swift and Xcode
  were unavailable on the Linux workspace, so the macOS CI run is the build
  and test authority.
