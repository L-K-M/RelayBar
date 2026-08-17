#!/usr/bin/env bash
# Cuts a release: bumps the version, commits, tags "v<version>", and with --push
# pushes branch + tag — which triggers .github/workflows/release.yml to test,
# build, sign, notarize, and publish the GitHub Release. Unlike the sibling
# repos, CI does NOT inject the version at build time: Sparkle compares the
# committed build number, so the tag must match the committed MARKETING_VERSION
# (release.yml asserts this) and RELEASE_POST_BUMP increments the committed
# CURRENT_PROJECT_VERSION alongside every version bump. After CI publishes,
# follow the runbook (docs/system-specs/operations/build-and-release.md): the
# appcast, website, and cask steps stay manual and keychain-bound.
#
#   scripts/release.sh 1.5.0          # bump version + build number + README, commit, tag v1.5.0
#   scripts/release.sh 1.5.0 --push   # …also push the commit + tag (CI then publishes)
#   scripts/release.sh                # tag the current MARKETING_VERSION as-is
#
# Pre-releases: the xcode kind's version regex rejects hyphenated versions, so a
# beta needs RELEASE_VERSION_REGEX exported (and release.yml's tag-must-match gate
# still requires the committed MARKETING_VERSION to carry the same suffix).
#
# Usage: scripts/release.sh [X.Y[.Z]] [--push]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail

export RELEASE_APP_NAME="RelayBar Scion"
export RELEASE_KIND="xcode"
export RELEASE_XCODE_PROJECT="RelayBar.xcodeproj"
export RELEASE_XCODE_SCHEME="RelayBar"
export RELEASE_POST_BUMP="scripts/bump-build-number.sh"
export RELEASE_CI_NOTE="CI (release.yml) will now test, build, sign, notarize, and publish the GitHub Release for <tag>. Appcast/website/cask follow-ups stay manual — see docs/system-specs/operations/build-and-release.md."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
