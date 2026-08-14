# Task 053 — Stable Form Accessibility Labels

Status: Complete

Created: 2026-08-14

## Outcome

Make the principal tunnel and Remote Files forms announce control purpose
consistently in empty and populated states.

## Delivery Boundary

- Keep the current visible captions, placeholders, values, and layout.
- Use native SwiftUI accessibility labels and hints.
- Do not redesign focus order or add broad localization infrastructure.

## Work

- Label Profile name, SSH host, Remote path, Server, saved-host name, and
  saved-host SSH host controls explicitly.
- Label the reusable forwarding endpoint-type picker with its endpoint role.
- Hide duplicate purely visual captions from the accessibility tree once their
  controls have stable programmatic names.
- Update the application-shell and Remote Files system contracts.

## Acceptance

- Principal labels describe field purpose without using placeholder or value.
- Empty and populated forms retain the same programmatic field names.
- Listen and destination endpoint-type controls announce their distinct role.
- Visual captions remain unchanged but do not create duplicate announcements.
- The macOS build and relevant checks, including `git diff --check`, pass.
- Packaged-app VoiceOver inspection remains part of Task 032 manual acceptance.

## Evidence

- [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/31847424729)
  passed the test suite, warnings-as-errors checks, and unsigned Release build
  for the final implementation commit on 2026-08-14.
- The [follow-up GLM 5.3 review](https://github.com/L-K-M/RelayBar/actions/runs/31847423565)
  completed successfully with no actionable suggestion after the Add SSH Host
  fields were simplified to **Name** and **SSH host**.
- Every `EditorField` leaf was audited and has a stable explicit purpose label.
  Each forwarding endpoint branch labels its picker, address, port, or Unix
  socket path with the Listen or Destination role; locked-TCP branches retain
  the role through their address and port controls.
- `git diff --check origin/main...HEAD` passed on 2026-08-14. Swift, Xcode,
  Accessibility Inspector, and VoiceOver were unavailable on the Linux
  workspace; macOS CI is the build authority and packaged VoiceOver inspection
  remains tracked by Task 032.
