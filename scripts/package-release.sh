#!/usr/bin/env bash
# Builds a Release app via build-app.sh and packages it as
# .build/RelayBarScion.zip (printed on success). With a Developer ID
# Application certificate (or SIGNING_IDENTITY set) the app is signed for
# notarization; otherwise it is ad-hoc signed — which is what CI publishes
# (task 062) and what notarize-release.sh refuses outright.
#
# Usage: scripts/package-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/RelayBarScion.app"
ZIP="$ROOT/.build/RelayBarScion.zip"

"$ROOT/scripts/build-app.sh" release

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "$ZIP"
