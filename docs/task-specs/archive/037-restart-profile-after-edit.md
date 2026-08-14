# Task 037 — Editing a Live Profile Restarts It

Status: Complete

Created: 2026-08-14

## Outcome

Saving an edit to a profile that is starting, retrying, or running replaces
its definition and immediately relaunches it, instead of silently leaving
the tunnel stopped.

## Delivery Boundary

- Keep the existing replacement semantics: the old launch is stopped through
  the normal pipeline before the new definition is saved.
- Only non-tag edits restart; group-tag-only changes remain metadata-only and
  preserve phase, retries, pending browser work, and process ownership.
- Editing an inactive profile must not start it.

## Work

- Relaunch through the existing `start` path after a non-tag edit replaces a
  desired profile, so validation, retry, and error handling are unchanged.
- Add focused tests for the active-edit relaunch and the stopped-edit case.
- Update the tunnel-management and process-lifecycle system specs.

## Acceptance

- Renaming (or otherwise editing) a running profile returns it to running on
  the updated definition with exactly one additional master launch.
- Editing a stopped profile leaves it stopped and spawns no process.
- Tag-only edits still preserve the running phase.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `TunnelStore.update(_:)` previously computed `wasActive`, stopped the
  profile, saved, and returned; the new code starts the profile again through
  the unchanged start pipeline when it was desired before the edit.
- Two focused tests cover the active-edit relaunch (phase returns to running,
  master invocation count grows by one) and the stopped-edit case (phase
  stays stopped, no process spawned). The existing tag-only preservation
  tests continue to cover the metadata path.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
