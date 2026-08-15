# Task 039 — Duplicate Profile

Status: Complete

Created: 2026-08-14

## Outcome

A profile can be duplicated from its row menu, producing an independent copy
directly after the original so a connection can be cloned and tweaked
without retyping.

## Delivery Boundary

- The copy receives fresh profile and rule identities, inherits the resolved
  group tag, and always starts stopped.
- An explicitly named profile's copy gains a " copy" suffix; an unnamed
  profile's copy stays unnamed so the generated summary keeps displaying.
- No lifecycle change to running profiles: duplicating never starts, stops,
  or modifies the original.

## Work

- Add `TunnelStore.duplicate(_:)`, inserting after the source and persisting
  immediately like every other mutation.
- Add **Duplicate** to the row menu between Edit and Delete.
- Add focused store tests and update the tunnel-management system spec.

## Acceptance

- Duplicate appears in every row menu and creates a stopped, safe copy with
  new identities immediately after the original.
- The copy survives a reload (persistence) and passes `isSafeToRun`.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `TunnelStore.duplicate(_:)` copies the stored profile, regenerates profile
  and rule UUIDs, inserts at `index + 1`, and saves; the row menu wires it
  between Edit and Delete.
- Two focused tests cover identity freshness, placement, naming, grouping,
  persistence, and the unnamed-profile case.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
