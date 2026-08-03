# Task 030 — Show Version and Project Links

Status: Complete

Created: 2026-08-01

Issue: [#17 — Show version somewhere / add an About dialog](https://github.com/lx2026/RelayBar/issues/17)

## Outcome

Let users identify the installed RelayBar version and reach the official
website and source repository without locating the application bundle.

## Delivery Boundary

- Add a quiet footer after the existing General card in the in-popover Settings
  screen. Do not add an About card, duplicate app icon/name block, Dock icon,
  app menu, separate window, or second settings surface.
- Use remaining space to place the footer near the bottom in the default
  layout. When content grows, it follows the preceding content in the scroll
  flow and never floats over a control or caption.
- Read the marketing version and build number from the running app bundle.
  Do not duplicate release numbers in Swift source or fetch them from a
  network service.
- Display `RelayBar <version> (<build>)` as static secondary text with an
  adjacent borderless copy control. Confirm copying through an icon swap that
  does not move the layout and an equivalent VoiceOver announcement.
- Link only to the canonical RelayBar website
  (`https://lx2026.github.io/RelayBar/`) and GitHub repository
  (`https://github.com/lx2026/RelayBar`), opening them through the user's
  default browser.
- Keep update detection and installation in Task 028; this task remains useful
  and truthful when offline.
- At default text size and normal state, Settings must fit 380 × 440 points
  without a scrollbar. The existing scroll view remains the safety net for
  larger text, longer content, and captions.
- Packaged keyboard, VoiceOver, and Reduce Motion execution that requires the
  maintainer's system access is tracked in Task 032.

## Work

- Add a small testable bundle-information boundary with safe fallback text for
  missing or malformed development metadata.
- Add the version/build line, copy control, website action, and GitHub action
  to the Settings footer using native keyboard, help, and VoiceOver semantics.
- Cover metadata mapping, copy behavior and confirmation, link routing,
  fallbacks, and the expanded Settings layout in focused tests and light/dark
  visual evidence.
- Update the application-shell system spec and verification evidence.

## Acceptance

- A packaged RelayBar 1.3.0 build displays version 1.3.0 and build 6 from its
  bundle metadata; a later build changes the display through metadata alone.
- The adjacent copy control writes `RelayBar 1.3.0 (6)` to the pasteboard,
  provides a visible non-shifting confirmation, and announces success to
  VoiceOver.
- Website and GitHub actions open the canonical HTTPS URLs once in the default
  browser and expose descriptive accessibility labels.
- Missing development metadata shows a stable fallback without crashing or
  presenting a hard-coded release as current.
- The Settings screen has no scrollbar at 380 × 440 points under default text
  and normal state. The longest implemented caption remains reachable by
  vertical scrolling without clipping or overlap.
- Light/dark visual evidence covers the complete footer, its longest caption,
  and transient copy and update confirmation states without layout movement.
- Focused tests, strict tests, a warnings-as-errors Release build, visual
  evidence, and `git diff --check` pass; affected system specs are current
  before completion.
