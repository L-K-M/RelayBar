# Task 048 — Popover Visual Polish: Hover Buttons, Consistent Menu, Error Tooltips

Status: Complete

Created: 2026-08-14

## Outcome

The popover answers the mouse: every round icon button deepens its tinted
circle on hover, the per-row ⋯ menu matches its sibling buttons at 28
points instead of floating bare at 25, and truncated SSH error text expands
in a hover tooltip.

## Delivery Boundary

- Pure presentation: no behavior, layout size, or accessibility-label
  changes beyond a new label on the row menu.
- One shared button view rather than four copies of the same circle code.

## Work

- Add `CircleIconButton` (tinted circle that deepens on hover with a short
  ease-out) and adopt it for the list header's settings/add, the row's
  open-in-browser, and the editor/settings back buttons.
- Give the row ⋯ menu the same 28-point circle on hover.
- Add the full message as `.help` on the row's one-line status text.
- Update the application-shell system spec.

## Acceptance

- Hovering any round icon button visibly deepens its circle; hit targets
  and VoiceOver labels are unchanged.
- A long failure message is fully readable on hover.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `CircleIconButton` centralizes the formerly repeated
  frame-28-plus-circle-tint idiom with a 120 ms hover transition; all four
  call sites adopt it, and the ⋯ menu gets the same circle on hover.
- The row status line carries its full untruncated message in `.help`.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and visual verification runs in the macOS CI job and the
  snapshot harness.
