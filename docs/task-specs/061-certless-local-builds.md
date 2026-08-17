# Task 061 — Certless local builds

Status: In Review

Created: 2026-08-17

Follows: Task 060

## Outcome

`./scripts/build.sh` produces a runnable RelayBarScion.app on a Mac with no
Developer ID certificate, matching the sibling repositories — while the release
path remains exclusively Developer-ID signed, notarized, and stapled.

## Delivery Boundary

- No change to what ships: `notarize-release.sh` refuses an ad-hoc-signed app
  before submission, and `release.yml` still fails closed without the signing
  secrets.
- No Sparkle, feed, or key-custody changes.

## Work

- `build-app.sh`: when no Developer ID Application identity exists (or
  `SIGNING_IDENTITY=-`), sign ad-hoc — same inside-out component order, without
  `--options runtime`/`--timestamp` (ad-hoc rejects timestamps, and library
  validation has no team to match) — with a clear not-distributable notice.
- `notarize-release.sh`: fail fast unless the built app's signature chain shows
  a Developer ID Application authority.
- Update the README build section, AGENTS.md, the runbook's requirements, the
  stub headers, and the changelog.

## Acceptance

- On a certless Mac, `./scripts/build.sh` completes, the app launches, and the
  output states the build is ad-hoc and not distributable.
- With a certificate installed, behavior is byte-identical to before.
- `NOTARY_PROFILE=… ./scripts/notarize-release.sh` on an ad-hoc build exits
  non-zero before contacting Apple.
