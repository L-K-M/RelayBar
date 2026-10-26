#!/usr/bin/env bash
# Regenerates Sources/RelayBar/Resources/THIRD_PARTY_NOTICES.txt from the
# Swift packages Xcode resolved for the app, using swiftpm-notices.py and the
# overrides in third-party-notices.json. With --check it writes nothing and
# fails when the committed file differs (build-app.sh and CI run this).
#
# Both Package.resolved files are read: the Xcode project's governs the
# shipped app, the root one governs `swift test`. A package pinned
# differently in the two fails, so a Dependabot bump of only the SwiftPM side
# cannot leave the notices describing other versions than the app contains.
#
# Usage: scripts/third-party-notices.sh [--check] SOURCE_PACKAGES_DIR
#   SOURCE_PACKAGES_DIR is <derivedDataPath>/SourcePackages of an xcodebuild
#   run, e.g. .build/LocalDerivedData/SourcePackages after build-app.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=(--output)
if [[ "${1:-}" == "--check" ]]; then
  MODE=(--quiet --check)
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--check] SOURCE_PACKAGES_DIR" >&2
  exit 2
fi

python3 -I "$ROOT/scripts/swiftpm-notices.py" \
  --title "RelayBar Scion" \
  --resolved "$ROOT/RelayBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
  --resolved "$ROOT/Package.resolved" \
  --checkouts "$1" \
  --overrides "$ROOT/scripts/third-party-notices.json" \
  "${MODE[@]}" "$ROOT/Sources/RelayBar/Resources/THIRD_PARTY_NOTICES.txt"
