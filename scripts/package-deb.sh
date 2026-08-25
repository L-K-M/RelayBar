#!/usr/bin/env bash
# Packages a release .deb for the Linux system tray (task 063).
#
# Usage: VERSION=1.2.3 ./scripts/package-deb.sh
#
# Builds the tray product first (release), then stages the standard Debian
# tree and produces .build/relaybar-tray_${VERSION}_amd64.deb. The output
# path is fixed so CI can upload without parsing build output.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VERSION:?set VERSION=X.Y.Z before packaging}"

output=".build/relaybar-tray_${VERSION}_amd64.deb"

swift build -c release --product RelayBarTray

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

prefix="$stage/relaybar-tray"
install -d "$prefix/DEBIAN" \
    "$prefix/usr/bin" \
    "$prefix/usr/share/doc/relaybar-tray"
install -m 0755 ".build/release/RelayBarTray" "$prefix/usr/bin/relaybar-tray"
install -m 0644 README.md "$prefix/usr/share/doc/relaybar-tray/README.md"
install -m 0644 LICENSE "$prefix/usr/share/doc/relaybar-tray/copyright"

installed_size="$(du -sk "$prefix/usr" | cut -f1)"

cat >"$prefix/DEBIAN/control" <<CONTROL
Package: relaybar-tray
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Installed-Size: $installed_size
Depends: openssh-client, libgtk-3-0, libayatana-appindicator3-0.1
Recommends: libnotify-bin
Homepage: https://github.com/L-K-M/RelayBar
Description: RelayBar Scion SSH forwarding profiles in the Linux system tray
 Menu-bar companion for managing structured SSH forwarding profiles on
 Ubuntu through StatusNotifierItem/AppIndicator. Profiles are read from
 \$XDG_CONFIG_HOME/relaybar/tunnels.json using the same JSON tunnel records
 as the macOS app.
CONTROL

mkdir -p .build
dpkg-deb --root-owner-group --build "$prefix" "$output"
echo "wrote $output"
