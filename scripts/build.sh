#!/usr/bin/env bash
# Builds RelayBarScion.app from the command line and reveals it in Finder on
# success. Thin stub for the shared lkm-build engine; the heavy lifting stays in
# scripts/build-app.sh (xcodebuild + the inside-out Developer ID signing of
# Sparkle's XPC services, Autoupdate, Updater, and framework), which the engine
# runs as the swiftpm-kind assemble script. With a Developer ID Application
# certificate the build is distributable (set SIGNING_IDENTITY to pick one);
# without one it is ad-hoc signed — runs locally, can't be notarized.
#
# Usage: scripts/build.sh [--clean] [--debug] [--run] [--install] [--zip] [--dmg]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail
export BUILD_APP_NAME="RelayBar Scion"
export BUILD_KIND="swiftpm"
export BUILD_PRODUCT_NAME="RelayBarScion"
export BUILD_SWIFTPM_ASSEMBLE="scripts/build-app.sh"
export BUILD_PRODUCT_PATH=".build/RelayBarScion.app"
export BUILD_CLEAN_PATHS=".build"
export BUILD_INVOKED_AS="scripts/build.sh"
BIN="${LKM_BUILD_BIN:-lkm-build}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-build not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
