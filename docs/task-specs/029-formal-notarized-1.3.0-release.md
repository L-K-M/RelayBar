# Task 029 — Formal Notarized 1.3.0 Release

Status: In Progress

Created: 2026-07-30

Started: 2026-07-30

## Outcome

Publish RelayBar 1.3.0 as the stable universal macOS release, signed with the
maintainer's Developer ID, accepted and stapled by Apple, and distributed as
one immutable archive through GitHub and the Homebrew cask.

## Delivery Boundary

- Release the exact accepted source commit under the annotated tag `v1.3.0`.
- Keep the marketing version at 1.3.0 and start the stable candidate at build
  6, after the 1.3.0-beta.1 build 5. Increment the build again after any
  post-freeze change to the application.
- Distribute one canonical `RelayBar.zip`; GitHub, direct-download
  documentation, and the Homebrew cask must identify the same bytes.
- Promote the user-visible work completed after 1.2.1, including the
  1.3.0-beta.1 changes and the later Remote Files navigation and preview
  improvements.
- Limit code changes to release blockers. Keep new product work in a later
  task.
- Preserve prior releases and never replace a published `v1.3.0` asset in
  place. Withdraw the release or issue a later patch if the artifact is bad.
- Treat earlier notarized local test builds as evidence only; build and
  notarize the public archive afresh from the release commit.
- Keep certificates, notary credentials, keychain profile names, and other
  local release configuration out of the repository and public evidence.
- Preparing, reviewing, committing, or merging this task does not authorize
  notarization, publication, Homebrew changes, or deployment. Obtain explicit
  approval for the release deployment before the first such action.

## Work

- Finalize the 1.3.0 changelog and release notes from the accepted task and
  verification records, with a stable release date and tag link.
- Confirm the app and Xcode metadata consistently report version 1.3.0 with a
  build number greater than the beta's build 5, macOS 13 minimum, and the
  production bundle identifier.
- Freeze a clean, synchronized release commit and run the complete tests,
  warnings-as-errors Xcode Release build, property-list validation,
  `git diff --check`, and the documented dependency, license, security, and
  manual regression checks.
- Build the universal archive from that exact commit. Verify both executable
  architectures, the hardened-runtime Developer ID signature, timestamp,
  bundled notices, resource pruning, and matching executable/dSYM UUIDs.
- Submit the archive to Apple, wait for acceptance, staple and validate the
  ticket, rebuild the ZIP from the stapled app, and record the notarization
  submission ID and SHA-256 without recording credentials.
- Extract the final ZIP in a clean temporary location and recheck its version,
  build, architectures, code signature, notarization ticket, Gatekeeper
  assessment, launch, and representative forwarding and Remote Files flows.
- Create the annotated `v1.3.0` tag on the verified commit and publish a
  non-draft, non-prerelease GitHub release with the final ZIP and release
  notes. Download the public asset independently and prove it has the recorded
  SHA-256 and passes the same signature, ticket, and Gatekeeper checks.
- After the release asset is publicly verified, update the README and project
  website from 1.2.1 to 1.3.0, validate every release link, and update the
  maintainer Homebrew cask to version 1.3.0 and the final archive SHA-256.
- Verify a clean Homebrew install and an upgrade from 1.2.1 where available,
  including launch, reported version, Gatekeeper, archive equivalence, and
  uninstall without user-data removal.
- Record release, public-download, documentation, and Homebrew evidence under
  `docs/verification/`; update the build-and-release system spec if the proven
  procedure differs from it.

## Acceptance

- The stable GitHub release is tagged `v1.3.0`, is neither a draft nor a
  prerelease, and its tag resolves to the exact verified release commit.
- Its sole application archive contains RelayBar 1.3.0 with a build number
  greater than 5, the production bundle identifier, macOS 13 minimum, and both
  `arm64` and `x86_64` executable slices.
- The extracted app has a valid timestamped hardened-runtime Developer ID
  signature, a valid stapled Apple ticket, matching executable/dSYM UUIDs, and
  a successful Gatekeeper assessment identifying a notarized Developer ID.
- Complete automated, build, metadata, security, license, clean-extraction,
  launch, and representative forwarding and Remote Files checks pass against
  the release commit and final artifact.
- The independently downloaded GitHub asset exactly matches the recorded
  SHA-256; no post-verification repackaging or asset replacement occurs.
- The changelog and release notes accurately cover the stable changes since
  1.2.1, and all public stable-version and direct-download references point to
  the verified 1.3.0 release.
- `lx2026/tap/relaybar` identifies version 1.3.0 and the same SHA-256; current
  Homebrew style, strict online/signing audit, install or upgrade, launch,
  version, Gatekeeper, archive-equivalence, and uninstall checks pass.
- Release evidence records the commit, tag, build number, signing identity,
  notarization submission ID, SHA-256, commands and results, manual checks,
  public URLs, and any unavailable environment coverage without exposing a
  credential or local notary profile.
- The task moves to `docs/task-specs/archive/` only after the GitHub release,
  documentation, and Homebrew cask are publicly reachable and independently
  verified.
