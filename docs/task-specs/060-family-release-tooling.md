# Task 060 — Family release tooling

Status: In Review

Created: 2026-08-16

Related: Task 032 (release and manual acceptance)

## Outcome

RelayBar Scion uses the same release/build tooling contract as its sibling
repositories — one single-sourced version, thin `scripts/release.sh` and
`scripts/build.sh` stubs over the shared release-tool engines, a hardened CI
workflow, and a tag-triggered release workflow — without giving up this fork's
signed, notarized, byte-verified release posture.

## Delivery Boundary

- No release is cut, no tag pushed, and no artifact published; the workflow
  only runs when a maintainer pushes a `v*` tag, and it fails closed until the
  six signing/notarization repository secrets exist.
- Sparkle stays dormant: no `SUFeedURL`/`SUPublicEDKey`, no feed, no key
  custody changes. Task 032 continues to govern the first release's human
  acceptance.
- The maintainer-local notarization pipeline remains available and documented
  as the fallback.

## Work

- Single-source the version: `Packaging/Info.plist` expands
  `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`; `bump-build-number.sh`
  keeps the committed Sparkle build number monotonic on every version bump.
- Add the `release.sh`/`build.sh` engine stubs; teach `build-app.sh` the
  engine's `--debug` spelling.
- Harden `ci.yml` (concurrency, timeouts, pinned Xcode, manual dispatch) and
  add the test-gated, fail-closed `release.yml` that reuses
  `notarize-release.sh` and byte-verifies the published asset.
- Add the README version marker, family `.gitignore` baseline (untracking
  `.idea/`), script headers, an AGENTS.md toolchain section, and update this
  runbook.

## Acceptance

- `scripts/release.sh --check` and `scripts/build.sh --check` resolve config
  against the installed engines on a maintainer Mac.
- CI is green on the branch; `swift test` and the registry check pass.
- The runbook describes the implemented tag-triggered flow, and the first
  actual release still requires the maintainer decisions recorded in the pull
  request (secrets, feed ownership, Task 032 acceptance).
