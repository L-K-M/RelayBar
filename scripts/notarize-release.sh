#!/usr/bin/env bash
# Builds, signs, and packages a release (via package-release.sh), submits it with
# notarytool, waits, staples + validates the app, re-zips the stapled app as the
# final .build/RelayBarScion.zip (printed on success), and Gatekeeper-assesses it.
# Requires NOTARY_PROFILE, a notarytool keychain profile created with
# `xcrun notarytool store-credentials`.
#
# Usage: NOTARY_PROFILE=<profile> scripts/notarize-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

APP="$ROOT/.build/RelayBarScion.app"
ZIP="$ROOT/.build/RelayBarScion.zip"

"$ROOT/scripts/package-release.sh"

# build-app.sh falls back to ad-hoc signing when no Developer ID certificate is
# available; that build can never be notarized. Refuse it here, before a
# pointless round-trip to Apple — and before anything ad-hoc gets near a release.
if ! codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application"; then
  echo "The built app is not Developer ID signed (ad-hoc fallback?)." >&2
  echo "Install a Developer ID Application certificate or set SIGNING_IDENTITY, then rerun." >&2
  exit 1
fi

xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=4 "$APP"

echo "$ZIP"
