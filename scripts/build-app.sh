#!/usr/bin/env bash
# Builds and signs .build/RelayBarScion.app. With a Developer ID Application
# certificate in the keychain (or SIGNING_IDENTITY set), Sparkle's XPC services,
# Autoupdate, Updater, and framework are signed inside-out before the outer
# bundle so every nested boundary keeps a valid hardened-runtime identity —
# that build is what notarize-release.sh distributes. Without one, the build
# falls back to ad-hoc signing (same inside-out order, no hardened runtime or
# timestamp), which runs locally like the sibling apps' dev builds but can
# never be notarized or distributed; SIGNING_IDENTITY=- forces the fallback.
#
# Usage: scripts/build-app.sh [debug|release|--debug]   (default: release)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

case "$CONFIGURATION" in
  # --debug is what the shared lkm-build engine passes for a Debug build.
  debug|Debug|--debug)
    XCODE_CONFIGURATION="Debug"
    DESTINATION="platform=macOS"
    ;;
  release|Release)
    XCODE_CONFIGURATION="Release"
    DESTINATION="generic/platform=macOS"
    ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

cd "$ROOT"
DERIVED_DATA="$ROOT/.build/LocalDerivedData"
APP="$ROOT/.build/RelayBarScion.app"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning |
      sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "No Developer ID Application certificate found — falling back to ad-hoc signing." >&2
  echo "The app will run locally but cannot be notarized or distributed. For a" >&2
  echo "distributable build, install one or set SIGNING_IDENTITY to a certificate" >&2
  echo "shown by: security find-identity -v -p codesigning" >&2
fi

# Ad-hoc signatures reject --timestamp, and the hardened runtime's library
# validation has no team identity to match against ad-hoc-signed frameworks —
# so the fallback signs plainly (still inside-out), like the sibling apps'
# unsigned dev builds. notarize-release.sh refuses ad-hoc input outright.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  COMPONENT_SIGN_ARGS=(--force --sign -)
  BUNDLE_SIGN_ARGS=(--force --sign -)
else
  COMPONENT_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp
    --preserve-metadata=entitlements,requirements,flags)
  BUNDLE_SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp)
fi

# xcodebuild writes diagnostics to stdout and only the failure summary to
# stderr, so discarding stdout outright threw away every reason a build could
# fail and left the caller with a list of commands and no error text. Keep the
# quiet successful build, but hold the log and print the diagnostics on failure.
BUILD_LOG="$ROOT/.build/xcodebuild-$XCODE_CONFIGURATION.log"
mkdir -p "$ROOT/.build"

if ! xcodebuild \
  -project RelayBar.xcodeproj \
  -scheme RelayBar \
  -configuration "$XCODE_CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >"$BUILD_LOG" 2>&1
then
  echo "Build failed. Diagnostics from $BUILD_LOG:" >&2
  # A warning promoted by SWIFT_TREAT_WARNINGS_AS_ERRORS still prints as
  # "warning:", so both are worth showing; the tail is the fallback for a
  # failure that produced neither, such as a missing dependency.
  if ! grep -E "(error|warning): " "$BUILD_LOG" >&2; then
    tail -n 40 "$BUILD_LOG" >&2
  fi
  exit 1
fi

rm -rf "$APP"
cp -R "$DERIVED_DATA/Build/Products/$XCODE_CONFIGURATION/RelayBarScion.app" "$APP"

SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
if [[ ! -d "$SPARKLE_VERSION" ]]; then
  echo "Sparkle.framework is missing from the built app." >&2
  exit 1
fi

# Sparkle contains nested executable code. Sign every boundary inside-out so
# the final app seal and each helper retain a valid hardened-runtime identity.
for component in \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
  "$SPARKLE_VERSION/Autoupdate" \
  "$SPARKLE_VERSION/Updater.app"
do
  codesign "${COMPONENT_SIGN_ARGS[@]}" "$component" >/dev/null
done

codesign "${BUNDLE_SIGN_ARGS[@]}" "$SPARKLE_FRAMEWORK" >/dev/null
codesign "${BUNDLE_SIGN_ARGS[@]}" "$APP" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP"

for component in \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc" \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
  "$SPARKLE_VERSION/Updater.app" \
  "$SPARKLE_FRAMEWORK"
do
  codesign --verify --strict --verbose=2 "$component"
done

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Signed: ad-hoc (local use only — not distributable)"
else
  echo "Signed with: $SIGNING_IDENTITY"
fi
echo "$APP"
