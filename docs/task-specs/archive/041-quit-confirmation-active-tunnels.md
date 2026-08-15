# Task 041 — Quit Confirmation With Active Tunnels

Status: Complete

Created: 2026-08-14

## Outcome

Quitting while any profile is starting, retrying, or running asks once —
Stop and Quit, or Cancel — instead of SIGTERMinating every live connection
on a stray ⌘Q.

## Delivery Boundary

- With nothing active, Quit proceeds without a prompt.
- A deferred update install keeps precedence: it takes over termination and
  asks its own question, exactly as before.
- Both quit paths (⌘Q and the popover footer) share the confirmation; a
  confirmed quit still stops all managed processes via the existing
  `applicationWillTerminate` path.

## Work

- Confirm in `applicationShouldTerminate` when the store reports active
  tunnels, after the update-deferral check.
- Route the footer's Quit through the same delegate path instead of
  pre-stopping tunnels itself.
- Keep the alert copy pure and tested; update the application-shell system
  spec.

## Acceptance

- ⌘Q or footer Quit with two running tunnels shows the count and stops only
  after confirmation; Cancel leaves everything running.
- Quit with no active tunnels never prompts.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `applicationShouldTerminate` now confirms via `NSAlert` when
  `runningCount > 0` after the update-deferral branch; `TunnelStore.quit()`
  no longer pre-stops tunnels, so both entry points share the confirmation
  and the existing `applicationWillTerminate → stopAll` cleanup.
- `QuitConfirmation` holds the message and button copy with singular and
  plural tests.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
