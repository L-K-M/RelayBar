#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/RelayBarScion.app"
ZIP="$ROOT/.build/RelayBarScion.zip"

"$ROOT/scripts/build-app.sh" release

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "$ZIP"
