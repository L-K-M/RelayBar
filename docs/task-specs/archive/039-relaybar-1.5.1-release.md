# Task 039 — RelayBar 1.5.1 Stable Release

Status: Complete

Started: 2026-08-27

Accepted: 2026-08-27

## Outcome

Publish the accepted Task 038 changes as RelayBar 1.5.1 build 10 through one
Developer-ID-signed, Apple-notarized, stapled universal archive. GitHub,
Sparkle, project documentation, and the maintainer Homebrew cask identify the
same immutable release.

## Delivery Boundary

Included:

- the visible trailing Start All and Stop All group controls;
- the Homebrew quit-and-reopen lifecycle directive;
- version/build metadata, concise changelog and release notes;
- a stable `v1.5.1` tag and non-prerelease GitHub release;
- the signed production appcast and current download links;
- the maintainer cask at version 1.5.1 with the final archive SHA-256;
- installation of the final notarized application for maintainer use.

Excluded:

- unrelated product changes;
- replacing any published asset in place;
- weakening signing, notarization, Sparkle, Gatekeeper, or Homebrew checks;
- opening a pull request without a separate request.

## Work

- Set the marketing version to 1.5.1 and the monotonic build number to 10 in
  the application property list and Xcode project.
- Add concise release notes covering visible group controls and reliable
  Homebrew-managed upgrades.
- Freeze a clean release commit and run complete strict tests, snapshots,
  warnings-as-errors universal Release build, metadata, resource, license,
  dSYM, signature, and diff checks.
- Build, notarize, staple, rebuild, and independently verify the final ZIP.
- Push the release branch and annotated `v1.5.1` tag, publish one stable GitHub
  asset, and prove the anonymous download is byte-identical.
- Generate and verify the signed production appcast from the public immutable
  asset; update current download and version references.
- Update the maintainer cask to the same version, URL, and SHA-256 while
  retaining `uninstall quit: "com.lx2026.RelayBar"`; verify style, livecheck,
  running and stopped upgrade behavior, signature, ticket, Gatekeeper, and
  user-data preservation.
- Install and launch the final notarized 1.5.1 application.

## Acceptance

- `v1.5.1` resolves to the verified clean release commit and the GitHub release
  is stable, non-draft, non-prerelease, with one immutable `RelayBar.zip`.
- The archive contains RelayBar 1.5.1 build 10 for `arm64` and `x86_64`, with
  the production bundle identifier, macOS 13 minimum, timestamped hardened-
  runtime Developer ID signature, matching dSYM UUIDs, stapled ticket, and
  successful Gatekeeper assessment.
- Complete tests, snapshots, build, metadata, resource, license, feed, public-
  download, and `git diff --check` verification pass or record an explicit
  environment-only limitation.
- The appcast, README, website download links, changelog, GitHub release, and
  Homebrew cask consistently identify 1.5.1 and the same public archive.
- A cask-managed running RelayBar quits before replacement and reopens as build
  10; an initially stopped app remains stopped. Preferences and Application
  Support are unchanged.
- The final notarized build is installed at `/Applications/RelayBar.app` and
  running for the maintainer.
