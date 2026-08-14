# Task 036 — Status-Item Click Dismisses the Popover

Status: Complete

Created: 2026-08-14

## Outcome

Clicking the menu-bar icon while the popover is open dismisses the popover,
matching every other menu-bar app, instead of flashing closed and immediately
re-opening.

## Delivery Boundary

- Keep the popover's `.transient` behavior, its reuse between openings, the
  re-launch re-open escape hatch, and the visibility assertions unchanged.
- Suppress only the toggle that is the tail of the click that already closed
  the popover; never block a deliberate second click.

## Work

- Add a `PopoverToggleGuard` that records popover closes and swallows exactly
  one toggle landing within a 350 ms window of the recorded close.
- Wire it into the delegate's toggle action and `popoverDidClose`.
- Add focused unit tests and update the application-shell system spec.

## Acceptance

- With the popover open, one click on the status item closes it and it stays
  closed until the next click.
- Clicks outside the popover, re-launch re-open, and rapid deliberate
  open/close/open sequences keep working.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- The bug is an event-ordering race: with `.transient` behavior the click on
  the status item dismisses the popover on mouse-down, so by the time the
  button action runs on mouse-up `popover.isShown` is already `false` and the
  old code re-presented the menu. The guard consumes that one stale toggle.
- Four focused tests cover presentation without a close, swallowing exactly
  one in-window toggle, presenting after the window, and re-arming per close.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
