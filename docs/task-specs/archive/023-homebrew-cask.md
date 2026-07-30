# Task 023 — Homebrew Cask

Status: Complete

Created: 2026-07-26

Accepted: 2026-07-30

Issue: [#10 — Make it available on HomeBrew](https://github.com/lx2026/RelayBar/issues/10)

## Outcome

Make the notarized RelayBar application installable and removable through a
maintainer-owned Homebrew cask while preserving the exact upstream release
artifact.

## Delivery Boundary

- Publish `relaybar` as a cask in a maintainer-owned `lx2026/homebrew-tap`
  repository.
- Use the immutable, versioned GitHub release ZIP, its SHA-256 digest, the
  canonical project homepage, and the `RelayBar.app` artifact.
- Declare the actual macOS minimum and install the application without
  post-install scripts, signature changes, quarantine bypasses, or elevated
  privileges.
- Keep credentials, notarization configuration, and local release settings out
  of both public repositories.
- Defer submission to the official `homebrew/cask` repository until RelayBar
  satisfies the then-current Homebrew acceptance policy and the user separately
  approves that external pull request.

## Work

- Confirm that the `relaybar` cask token does not conflict with an existing open
  or closed Homebrew contribution.
- Create a minimal `Casks/relaybar.rb` in the maintainer-owned tap using the
  current stable release version, checksum, release URL, name, description,
  homepage, macOS requirement, and `app "RelayBar.app"` artifact.
- Test install, launch, Gatekeeper validation, version reporting, and uninstall
  on the supported macOS and architecture boundary.
- Run the current Homebrew cask style, audit, online, install, and uninstall
  checks from the official contribution guidance.
- Document the tap install command in the README and project website only after
  the cask is publicly reachable.
- Add cask version and checksum maintenance to the release system spec so each
  later stable release has an explicit update step.
- Record the official-tap eligibility check and any deferred submission work in
  verification evidence without treating popularity as an implementation
  failure.

## Acceptance

- `brew install --cask lx2026/tap/relaybar` installs the published universal,
  Developer-ID-signed, notarized RelayBar application.
- The installed bundle reports the cask's declared version, passes Gatekeeper,
  and contains the same application bytes as the verified upstream release
  after archive extraction.
- `brew uninstall --cask lx2026/tap/relaybar` removes the application without
  deleting RelayBar user data.
- Current Homebrew style, audit, online, install, and uninstall checks pass.
- The cask contains no custom installer, postflight script, quarantine bypass,
  credential, local path, or notarization-profile reference.
- README and website instructions distinguish direct download from the tested
  Homebrew command and point to the same stable version.
- Build-and-release documentation defines how to update and verify the cask for
  later releases.
- Publishing the tap, changing public documentation, or opening an official
  Homebrew pull request occurs only after explicit deployment approval.
