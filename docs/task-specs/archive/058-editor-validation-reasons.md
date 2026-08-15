# Task 058 — The Editor Explains Why Save Is Disabled

Status: Complete

Created: 2026-08-14

## Outcome

While the profile form is invalid, the action bar names the single first
blocking issue — bad port, missing host, conflicting listeners, pending
group name, missing Remote SOCKS policy — next to the disabled Save button
and as its tooltip, instead of leaving the user to guess.

## Delivery Boundary

- Presentation only: the hard gate stays `builtTunnel`/`isSafeToRun`
  unchanged; the caption mirrors those checks in the same order and stops at
  the first problem.
- Styling stays quiet (secondary text, info icon) so a pristine empty form
  reads as guidance, not an error shout.

## Work

- Add `firstValidationIssue` to the editor covering pending group names,
  empty rules, per-rule draft issues, the bind mask, the reverse-SOCKS
  policy, the host, and conflicting listeners.
- Give `ForwardingRuleDraft` a `validationIssue` mirror of its
  `forwardingRule` gate (internal, for tests).
- Render the caption above the action row and as the Save tooltip.
- Add draft validation tests, including issue/gate agreement; update the
  tunnel-management system spec.

## Acceptance

- Every state that disables Save names a reason; a valid form shows none.
- Any draft with no issue builds a valid rule; any draft with an issue does
  not (agreement test).
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `firstValidationIssue` walks the same checks as `builtTunnel` in the same
  order — group naming, rules present, per-rule validity, bind mask, reverse
  policy, host, listener conflicts — and the action bar shows it in quiet
  secondary text with a matching tooltip on the disabled button.
- Seven draft tests pin the per-field messages, dynamic-kind destination
  skipping, port ranges per direction, and issue/gate agreement.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
