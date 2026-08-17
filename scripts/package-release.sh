#!/usr/bin/env bash
# Builds a signed Release app via build-app.sh and packages it as the
# pre-notarization .build/RelayBarScion.zip (printed on success).
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
