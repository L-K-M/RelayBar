# Build and Release

## Requirements

- macOS 13 or newer
- Xcode command-line tools
- Developer ID Application certificate for packaged builds

## Commands

- `swift test` runs the package tests.
- `./scripts/build-app.sh` builds and signs `.build/RelayBar.app`.
- `./scripts/package-release.sh` creates `.build/RelayBar.zip`.
- `./scripts/notarize-release.sh` submits, waits, staples, and validates a release.

The Xcode target prunes unused renderer resources from the generated app bundle. It retains Highlighter's formatter and the two themes RelayBar selects, plus SwiftMath's default Latin Modern font, metrics, and bundled font licenses. It removes the other highlight themes, alternate math fonts, and SwiftMath's package-development conversion script. Source dependencies remain unchanged and every clean build reproduces the same pruning step.

Release builds generate a dSYM and then apply non-global symbol stripping to the installed executable. Debug builds remain unstripped. The dSYM and executable UUIDs must match before a release artifact is accepted.

The app is distributed outside the Mac App Store, uses the hardened runtime, and is intentionally not sandboxed.

## Homebrew cask

The maintainer-owned `lx2026/homebrew-tap` repository publishes
`Casks/relaybar.rb`. The cask installs the same immutable, versioned
`RelayBar.zip` attached to the stable GitHub release and pins its SHA-256. It
uses only the standard `app "RelayBar.app"` artifact, declares the real macOS
minimum, and does not bypass quarantine, re-sign the bundle, run postflight
scripts, or remove RelayBar user data.

After publishing and independently verifying a stable release:

1. update the cask version and SHA-256 to that exact release archive;
2. confirm its URL, homepage, macOS requirement, and app artifact;
3. run Homebrew style plus strict online and signing audits;
4. test install, launch, version, Gatekeeper, and uninstall behavior; and
5. confirm the extracted archive and cask installation contain the same signed
   application.

RelayBar does not update itself, so the cask must not declare
`auto_updates true`. Users update with
`brew upgrade --cask lx2026/tap/relaybar`.

## Project Website

The GitHub Pages site is a build-free static site under `docs/`. Its
`index.html`, `styles.css`, and local image assets are sufficient to render the
page; it does not require a generated page runtime or third-party font request.
Release download links identify the current stable version explicitly.
