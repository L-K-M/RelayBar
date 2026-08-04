# Task 033 verification

Verified: 2026-08-02

## Result

The private signed update rehearsal completed successfully without publishing
a release, production appcast, website change, or Homebrew cask. The original
failure was reproduced in Sparkle logs: the app requested the production
appcast and received 404 because a `defaults` value visible to the CLI was not
visible through Foundation. The private feed selector now uses a guarded,
process-scoped `--maintainer-update-feed` launch argument and fails closed when
that argument is invalid.

## Signed update evidence

- Notarized rehearsal build 7 submission:
  `0108d8a9-db57-4b74-b296-6b41ea5ffb3b`.
- Notarized rehearsal build 8 submission:
  `19239f08-6830-4681-b074-bca22a171199`.
- The staged build 8 archive and private feed archive were byte-identical with
  SHA-256 `66ce077672574e9a20a1b3ad556175cc1c65245067e71c91c2a3be8224f42da1`.
- `verify-private-update-feed.sh` verified the feed signature, archive
  signature, embedded/keychain public-key match, enclosure length, version,
  and exact loopback URL.
- The installed notarized build 7 was launched with
  `--maintainer-update-feed http://127.0.0.1:8765/appcast.xml`. A user-initiated
  **Check for Updates…** presented Sparkle's standard UI and installed build 8.
  `/Applications/RelayBar.app/Contents/Info.plist` then reported build 8 and
  the relaunched process used the updated application.

## Correctness checks

- The final complete Swift suite executed 229 tests with 15 expected opt-in
  skips and zero failures.
- Focused integration coverage proves master and control-helper processes stay
  in the deferred-install gate, an SSH master ignoring SIGTERM is force-killed
  after the grace period, the visible waiting count stays positive while
  processes drain, and deferred evaluation reads settled `@Published` state.
- The Sparkle-linked Release target passed complete Swift concurrency checking
  with app-target warnings treated as errors.
- Property-list validation, shell syntax checks, the private feed verifier, and
  `git diff --check` passed.
- A final read-only Fable review found no unresolved correctness or security
  defect in the Task 033 boundary.

## Cleanup and installed state

The private loopback server was stopped and port 8765 is closed. Foundation
confirmed that `RelayBarMaintainerUpdateFeedURL`, `SUFeedURL`, `SULastCheckTime`,
and `SUSkippedVersion` are absent and automatic checks remain off. The final
reviewed build 7 was notarized under submission
`cc1b9ce9-7699-4771-844c-427779f90ca2`, stapled, accepted by Gatekeeper, and
installed in `/Applications`; its normal running process has no private-feed
argument. Its stapled ZIP SHA-256 is
`6c6592129339b114a3ae8c1fb647a0e2c46cb8fd5dbab92cd4c09b9dfbe41c68`.
