# Task 033 — Private Update Rehearsal Correctness

Status: Complete

Created: 2026-08-02

Discovered during: Task 032

## Outcome

Make the signed local prior-to-newer update rehearsal reliable, truthful, and
safe enough to validate RelayBar before any public release or appcast exists.

## Delivery Boundary

- Keep production feed configuration, signing requirements, and publication
  scripts unchanged and strict.
- Permit a private feed only through an undocumented, process-scoped launch
  argument containing an explicit-port HTTP loopback URL; do not accept LAN,
  remote, file, or arbitrary HTTPS URLs.
- Do not publish a release, appcast, website change, or Homebrew cask.
- Keep approval-dependent, public, scheduled, macOS 13, and broader manual
  acceptance work in Task 032.

## Work

- Replace the probe-then-present sequence with one user-initiated Sparkle check.
- Add guarded maintainer-only loopback feed selection and isolated private
  appcast staging and verification commands.
- Keep a deferred update visible and resume it only after actual managed SSH
  process exits, including a quit attempted during deferral.
- Build notarized prior and newer artifacts, stage the signed loopback feed,
  and operate the installed app through the macOS UI.
- Restore the prior app and stop the loopback server after the rehearsal, then
  obtain a fresh read-only Fable review.

## Acceptance

- Unit tests cover single-pass checks, loopback URL rejection, persistent
  deferred state, waiting for master and control-helper exits, and forced
  termination when an SSH child ignores SIGTERM.
- The strict Xcode app build, complete test suite, private feed verifier,
  property-list checks, and `git diff --check` pass.
- A macOS UI check observes the standard Sparkle update experience, completes
  a signed update from the notarized prior build to the notarized newer build,
  and the installed metadata confirms the new build.
- The rehearsal leaves no maintainer feed override or private loopback server,
  and restores the pre-test installed build.
- A fresh Fable review identifies no unresolved correctness or security defect
  inside this task's delivery boundary; remaining acceptance work is recorded
  in Task 032.
