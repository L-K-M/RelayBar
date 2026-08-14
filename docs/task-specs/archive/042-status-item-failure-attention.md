# Task 042 — Status Item Failure Attention

Status: Complete

Created: 2026-08-14

## Outcome

Keep exhausted tunnel failures visible when RelayBar's popover is closed and
give assistive technology an accurate compact status summary.

## Delivery Boundary

- Retain one named, position-preserving `NSStatusItem` for the app lifetime.
- Use static monochrome template symbols with a drawn fallback.
- Do not animate, post user notifications, or depend on color for failure
  attention.

## Work

- Derive stopped, active, and issue states with active and failed counts.
- Let any failed profile take precedence in the icon state.
- Add a distinct issue symbol and equivalent drawn fallback.
- Update the button accessibility value and native help whenever state or
  counts change.
- Post one accessibility value-change notification on state transitions, not
  routine count-only updates.
- Cover state priority, counts, and pluralized accessibility copy with tests.
- Update the application-shell system contract.

## Acceptance

- Zero-active/zero-failed, active, and failed fixtures produce distinct states.
- A failed profile changes the closed-popover icon without animation or color.
- The status button reports correctly pluralized active and failed counts.
- Count-only changes refresh the accessibility value without recreating the
  status item or needlessly replacing its image.
- Symbol lookup failure still leaves a distinct clickable issue glyph.
- Relevant automated checks and `git diff --check` pass.

## Evidence

- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31847355773)
  passed the full test suite, warnings-as-errors checks, and unsigned Release
  build for the reviewed implementation on 2026-08-14.
- The [follow-up GLM 5.3 review](https://github.com/L-K-M/RelayBar/actions/runs/31847354497)
  completed successfully with no actionable suggestion after both knockout
  paths gained graphics-state isolation, image replacement became directly
  testable, and state transitions gained a non-chatty accessibility signal.
- Focused fixtures cover stopped, active, and issue priority, pluralized counts,
  and state-only image replacement. Source review confirmed the app retains its
  single named status item and the drawn issue fallback remains clickable.
- `git diff --check origin/main...HEAD` passed on 2026-08-14. Swift, Xcode, and
  VoiceOver were unavailable on the Linux workspace; macOS CI is the build and
  test authority, and packaged assistive-technology acceptance remains Task
  032.
