# Task 038 — Reliable Homebrew Upgrade and Visible Group Controls

Status: Complete

Accepted: 2026-08-27

Sources: [GitHub issue 28](https://github.com/lx2026/RelayBar/issues/28) and
[GitHub issue 29](https://github.com/lx2026/RelayBar/issues/29)

## Outcome

A Homebrew upgrade from an installation carrying RelayBar's updated cask
receipt closes a running RelayBar before replacing its bundle and reopens the
newly installed app. Named groups expose Start All and Stop All in the main
tunnel list without requiring the actions menu.

## Delivery Boundary

Included:

- the maintainer-owned `lx2026/homebrew-tap` RelayBar cask;
- named-group headers in RelayBar's 380-point menu-bar window;
- state-aware enablement, keyboard access, help, and accessibility labels;
- focused automated, visual, and real Homebrew-upgrade verification;
- affected system specifications and recorded verification evidence;
- a signed local application installed for maintainer review.

Excluded:

- changes to per-profile or group lifecycle semantics;
- automatic relaunch after an ordinary uninstall;
- custom kill scripts, postflight scripts, or bypassing Homebrew's `--no-quit`
  override;
- a version bump, release, appcast change, cask publication, or issue closure.

## Work

### 1. Make Homebrew own the upgrade lifecycle

- Add `uninstall quit: "com.lx2026.RelayBar"` to the RelayBar cask, using the
  app's committed `CFBundleIdentifier` rather than a process-name match.
- Rely on Homebrew's native upgrade contract: quit a running registered bundle,
  replace the application, register the new bundle, and reopen only an app that
  Homebrew successfully quit for that upgrade.
- Document Homebrew's receipt boundary: uninstall artifacts are captured when
  a cask is installed. Updating the tap does not rewrite an already-installed
  legacy receipt, so an installation made before this directive must be
  reinstalled once or manually quit for its first subsequent upgrade.
- Do not add a signal fallback, broad process match, custom script, `zap`, or
  user-data removal.
- Exercise a real cask-managed 1.4.0-to-1.5.0 upgrade with the old-version
  fixture carrying the updated quit receipt and RelayBar running.
  Record the old and new process identities, installed version/build, release
  checksum, signing, notarization, Gatekeeper, relaunch, and preservation of
  preferences and Application Support.
- Also verify that upgrading while RelayBar is not running does not launch it.

### 2. Surface group Start All and Stop All

- Keep the group name leading and place persistent Start All and Stop All icon
  buttons at the trailing side immediately before the group actions menu. The
  buttons must not depend on pointer hover or menu focus to become visible.
- Preserve the existing state contract: Start All is enabled when at least one
  member is inactive; Stop All is enabled when at least one member is starting,
  running, or retrying. Mixed groups enable both.
- Call the existing `TunnelStore.startGroup` and `stopGroup` paths unchanged.
  Profiles outside the canonical group remain unaffected.
- Keep Restart All in the group actions menu with its existing active-member
  enablement. Keep Rename Group and Ungroup All there. Do not duplicate Start
  All or Stop All in that menu.
- Give each visible control an explicit accessibility label and help text that
  names the action and group. Preserve keyboard focus and disabled-state
  semantics.
- Truncate long group names before they can displace the lifecycle controls or
  create horizontal scrolling. Ungrouped sections do not receive group controls.

### 3. Verify and document

- Add or update focused coverage for the group-header layout and enabled states,
  including stopped, active, mixed, long-name, light, and dark evidence where
  the current harness can represent them.
- Update the tunnel-management, verification, and release-operation system
  specifications to describe the visible controls and cask upgrade lifecycle.
- Record the commands, screenshots, and manual evidence used to accept the task.

## Acceptance

- A named group always shows Start All and Stop All at the trailing side before
  its actions menu. Their enabled states are correct for all-stopped,
  all-active, and mixed membership.
- Activating either visible control produces the same scoped lifecycle behavior
  already covered for the corresponding former menu command.
- Restart All, Rename Group, and Ungroup All remain available from the group
  actions menu; ungrouped sections remain label-only.
- Long names, many sections, keyboard navigation, light/dark appearance, and
  the fixed 380 × 440 window show no clipping, overlap, or horizontal scrolling.
- VoiceOver identifies `Start all tunnels in <group>` and
  `Stop all tunnels in <group>`, and disabled controls remain discoverable.
- The cask contains exactly `uninstall quit: "com.lx2026.RelayBar"` and no
  broader quit, signal, script, or data-removal directive.
- During a real Homebrew upgrade from a receipt containing the quit directive
  with RelayBar running, the pre-upgrade PID exits before bundle replacement
  completes, build 1.5.0 (9) installs, and one new
  `/Applications/RelayBar.app` process starts. The installed application
  matches the official artifact and passes strict signature, stapler, and
  Gatekeeper checks.
- Verification records that a legacy receipt created without the directive is
  not changed retroactively and needs one reinstall or manual quit before its
  first later upgrade; this transition limitation is not described as passing.
- During the same upgrade with RelayBar initially stopped, Homebrew leaves it
  stopped. Upgrade and uninstall checks preserve RelayBar preferences and
  Application Support.
- Relevant tests, snapshot capture, the warnings-as-errors signed application
  build, and `git diff --check` pass. Updated system specs and verification
  evidence describe the implemented state.
- The signed review candidate is installed at `/Applications/RelayBar.app`, is
  running, and is left for maintainer review without publishing either branch.
