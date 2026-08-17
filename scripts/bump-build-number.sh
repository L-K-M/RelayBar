#!/usr/bin/env bash
# Increments CURRENT_PROJECT_VERSION (the Sparkle build number) in the pbxproj.
# Run by scripts/release.sh via RELEASE_POST_BUMP so every version bump also gets
# a fresh, strictly increasing build number — Sparkle compares builds, not the
# marketing version, and the release runbook requires committed monotonic builds
# (docs/system-specs/operations/build-and-release.md). Exits non-zero on any
# surprise, which makes lkm-release roll the whole bump back.
#
# Usage: scripts/bump-build-number.sh   (no arguments; also fine standalone)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PBXPROJ="RelayBar.xcodeproj/project.pbxproj"

# Read every occurrence: if the configurations have diverged (a hand-edit), the
# distinct values arrive newline-joined, fail the numeric check, and the release
# stops instead of silently normalizing both to the same next number — which
# could reuse a build number the appcast already published.
current="$(awk -F' = |;' '/CURRENT_PROJECT_VERSION = /{print $2}' "$PBXPROJ" | sort -u)"
[[ "$current" =~ ^[0-9]+$ ]] || {
  echo "error: CURRENT_PROJECT_VERSION must be one numeric value across all configurations in $PBXPROJ (got '${current//$'\n'/, }')" >&2
  exit 1
}
next=$((current + 1))

sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1${next};/g" "$PBXPROJ"

# Both build configurations must move together; anything else means the sed
# missed and the release must not proceed.
count="$(grep -c "CURRENT_PROJECT_VERSION = ${next};" "$PBXPROJ")"
[[ "$count" -eq 2 ]] || {
  echo "error: expected 2 CURRENT_PROJECT_VERSION = ${next}; lines after the bump, found ${count}" >&2
  exit 1
}

echo "Build number: ${current} -> ${next}"
