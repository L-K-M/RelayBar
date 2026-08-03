# Task 032 — Release and Manual Acceptance Verification

Updated: 2026-08-02

Result: In progress. VoiceOver inspection is excluded by maintainer decision.
The maintainer approved local notarization and installation of 1.4.0 build 7,
then approved publication of the verified archive as a beta. Stable appcast,
website-download, and Homebrew publication remain pending.

## Maintainer checklist

### Settings footer

- [x] Open the locally built RelayBar and confirm Settings fits its default
  popover without a scrollbar or overlap.
- [x] Confirm the footer displays `RelayBar 1.4.0 (7)`. Copy it, paste into a
  text field, and confirm the value is exact and the copy icon changes without
  moving adjacent content.
- [x] Open **Website** and **GitHub** and confirm each opens once in the default
  browser at the canonical RelayBar URL.
- [x] With macOS Keyboard navigation enabled, use Tab/Shift-Tab through Back,
  both toggles, Copy, Check for Updates, Website, and GitHub. Activate controls
  with Space or Return and use Escape to return to the tunnel list.
- [x] Enable Reduce Motion, repeat Copy and Check for Updates, and confirm
  feedback does not depend on movement or shift the footer.
- [x] Increase system text size and confirm every Settings control remains
  reachable vertically without horizontal clipping or overlap.
- [x] Confirm **Automatic Updates** uses the promised weekly-check copy,
  persists an intentional toggle change across relaunch, and adds no badge or
  status to the tunnel list. A clean first launch defaults off; an existing
  installation may retain its previous choice. Restore the preferred setting
  after the check.
- [x] Before the production appcast is published, **Check for Updates…** should
  end with the concise retry state. Close and reopen Settings and confirm the
  transient result is gone.

### Profile editor

- [x] Open an existing profile. Confirm Name receives focus without moving the
  form and every section remains evenly inset from both popover edges.
- [x] Open New Profile and confirm the same balanced insets and no horizontal
  scrollbar.
- [x] Add enough forwarding-rule content to scroll vertically. Confirm the
  vertical scrollbar does not shift or clip the form and no horizontal
  scrollbar appears.
- [x] Move focus through visible fields, then verify Cancel preserves the saved
  profile and Save Changes still persists a valid edit.

### Signing and release

- [x] The Keychain account `com.lx2026.RelayBar` public key matches the
  `SUPublicEDKey` embedded in RelayBar.
- [x] Authorize a local Sparkle sign/verify round trip without publishing its
  disposable payload.
- [ ] Export an encrypted offline recovery key to a maintainer-chosen secure
  location and restore-test it in an isolated environment.
- [x] Build, notarize, staple, and Gatekeeper-assess the 1.4.0 build 7 universal
  candidate; verify nested signatures, architectures, dSYM UUIDs, and the
  installed `/Applications/RelayBar.app`.
- [x] After publication approval, publish the verified archive as a GitHub
  prerelease and verify the anonymously downloaded public asset.
- [ ] Record the stable signed appcast, prior-to-newer manual/scheduled updates,
  active-tunnel choices, failure cases, and Homebrew
  install/update/uninstall evidence.

### Minimum supported system

- [ ] On an actual macOS 13 host, repeat the Edit/New/long-scrolled profile
  checks and record the OS/build and screenshots. The structural deployment
  target check alone does not satisfy this item.

## Existing automated evidence

- The strict suite passes 229 tests with 15 expected opt-in skips.
- Fresh light/dark Settings, New/Edit Profile, and scrolled-editor snapshot
  suites pass, including rendered horizontal-containment assertions.
- The RelayBar-target warnings-as-errors universal Release build passes. The
  Developer-ID-signed app, Sparkle nested code, architectures, macOS 13 minimum,
  and executable/dSYM UUIDs verify.
- `plutil`, shell syntax checks, and `git diff --check` pass.

## Evidence log

- 2026-08-02: The maintainer approved notarizing and installing the local
  candidate. The next monotonic identity is RelayBar 1.4.0 build 7; publication
  remains unapproved.
- 2026-08-02: Apple accepted notary submission
  `0406cd1a-4660-4552-a312-7e1f590ee3c7`. Stapler and Gatekeeper accepted the
  universal app; its executable and dSYM UUIDs match for `x86_64` and `arm64`.
  The final ZIP SHA-256 is
  `8a6c622ffea12e87ffc3cf63c2cd0ab60fcde2808febf7e0ac3c83d9fdcddc95`.
  The prior 1.3.0 build 6 app was moved to Trash as a recoverable backup, the
  verified candidate was installed at `/Applications/RelayBar.app`, and the
  installed executable matches the notarized candidate.
- 2026-08-02: The unlocked login Keychain returned the same public EdDSA key
  embedded in `Packaging/Info.plist`. After maintainer authorization, Sparkle's
  `sign_update` signed and verified a disposable local payload. The payload was
  moved to Trash and nothing was published.
- 2026-08-02: The maintainer reported that every Settings-footer and profile-
  editor check above passed on macOS 27.0 build 26A5388g. VoiceOver inspection
  remains waived, and the separate macOS 13 check remains open.
- 2026-08-02: The maintainer approved a beta publication. Commit
  `e260310834b3eeca3cb4a4792846f1bf933edd9e` was tagged
  `v1.4.0-beta.1`; Apple accepted notary submission
  `7106bfde-31d4-4d1f-b965-7eca2f28a181`. The stapled universal archive was
  published as the non-draft GitHub prerelease
  [RelayBar 1.4.0 Beta 1](https://github.com/lx2026/RelayBar/releases/tag/v1.4.0-beta.1).
  Its final `RelayBar.zip` is 6,528,677 bytes with SHA-256
  `358116688d81e9f1c9fe38070cbd4f0dbd7686f0eecb767b1d921bc80661a80a`.
  An anonymous download was byte-identical and passed clean extraction,
  strict signature, stapled-ticket, Gatekeeper, version/build, universal-
  architecture, retained-resource, and launch checks. The stable appcast,
  website download, and Homebrew cask were deliberately left unchanged.
