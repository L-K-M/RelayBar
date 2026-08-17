# Task 062 — Unsigned GitHub releases

Status: In Review

Created: 2026-08-17

Follows: Task 061

## Outcome

Tag-triggered releases publish an ad-hoc-signed `RelayBarScion.zip` — the same
unsigned, manually-enabled release model as the sibling family apps — instead
of failing closed on absent Developer ID and App Store Connect secrets.

## Authorities and Constraints

- Explicit maintainer decision (2026-08-17), reversing task 061's release-path
  boundary. 061 deliberately kept releases Developer-ID signed and recorded
  that `release.yml` fails closed without the signing secrets; this spec
  supersedes that boundary and is recorded for the same reason.
- The repository holds no signing secrets: the v2.0.1 release run failed at the
  secrets gate and published nothing, which is what prompted the decision.
- Ad-hoc signatures cannot be notarized; Sparkle publication stays dormant
  while this fork ships no feed, and `notarize-release.sh` keeps refusing
  ad-hoc input.

## Delivery Boundary

- Included: `release.yml` builds with `SIGNING_IDENTITY=-` through
  `package-release.sh` (inside-out Sparkle component signing) and publishes
  with unsigned-build release notes; runbook, README, AGENTS.md, changelog,
  and the `release.sh`/`package-release.sh` headers are updated to match.
- Excluded: no DMG, appcast, or cask channel is added; the maintainer-local
  notarized pipeline and its strict publication order are unchanged; no
  signing secret is ever added to the repository.

## Work

- `release.yml`: drop the secrets gate, keychain import, notary profile, and
  `notarize-release.sh` step; keep the tag/version gate and the
  published-asset byte-compare; name the job "Build & publish (unsigned)".
- Documentation as listed under Delivery Boundary.

## Acceptance

- A `v*` tag push on a commit carrying this spec's changes produces a green
  release run with no signing secrets configured in the repository.
- The published `RelayBarScion.zip` is byte-identical to the built archive,
  and the release notes state the Gatekeeper bypass.
- `NOTARY_PROFILE=… ./scripts/notarize-release.sh` on the published (ad-hoc)
  build still exits non-zero before contacting Apple.
