#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-}"
PORT="${2:-}"
OUTPUT_DIRECTORY="${3:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.lx2026.RelayBar}"

if [[ -z "$ARCHIVE" || -z "$PORT" || -z "$OUTPUT_DIRECTORY" ]]; then
  echo "Usage: $0 <final-stapled-RelayBar.zip> <loopback-port> <new-output-directory>" >&2
  exit 2
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "Archive not found: $ARCHIVE" >&2
  exit 1
fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1024 || PORT > 65535 )); then
  echo "The loopback port must be an integer from 1024 through 65535." >&2
  exit 1
fi
if [[ -e "$OUTPUT_DIRECTORY" ]]; then
  echo "The private staging directory already exists: $OUTPUT_DIRECTORY" >&2
  exit 1
fi

SPARKLE_BIN="${SPARKLE_BIN:-$(find "$ROOT/.build" "$HOME/Library/Developer/Xcode/DerivedData" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d -print -quit 2>/dev/null)}"
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "Sparkle release tools were not found. Resolve the Xcode packages first." >&2
  exit 1
fi

mkdir "$OUTPUT_DIRECTORY"
cp "$ARCHIVE" "$OUTPUT_DIRECTORY/RelayBar.zip"
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "http://127.0.0.1:$PORT/" \
  --link "https://lx2026.github.io/RelayBar/" \
  --maximum-versions 1 \
  "$OUTPUT_DIRECTORY"

"$ROOT/scripts/verify-private-update-feed.sh" \
  "$OUTPUT_DIRECTORY/appcast.xml" \
  "$OUTPUT_DIRECTORY/RelayBar.zip" \
  "$PORT"
echo "$OUTPUT_DIRECTORY"
