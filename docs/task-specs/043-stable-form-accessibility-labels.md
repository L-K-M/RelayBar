# Task 043 — Stable Form Accessibility Labels

Status: In Progress

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
