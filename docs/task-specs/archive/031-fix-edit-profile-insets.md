# Task 031 — Fix Edit Profile Insets

Status: Complete

Created: 2026-08-01

Issue: [#19 — Edit Profile content is not horizontally centered](https://github.com/lx2026/RelayBar/issues/19)

## Outcome

Keep the Edit Profile form inside the menu popover with balanced horizontal
insets instead of shifting its scroll content against the left edge.

## Delivery Boundary

- Preserve the 380 × 440 point popover, 16-point editor content insets, current
  form controls, vertical scrolling, header, and action bar.
- Fix the shared in-popover scroll-content pattern used by the editor and
  Settings rather than adding an edit-only offset or widening the popover.
- Do not change profile data, validation, forwarding behavior, or save/cancel
  semantics.
- Human focus, visible-scrollbar, and minimum-host execution on an actual
  macOS 13 system is tracked in Task 032.

## Work

- Make the vertical scroll viewport constrain padded content to its width so
  focused-control chrome cannot inflate the content beyond the viewport and
  produce horizontal overflow or a focus-driven offset.
- Apply the same constrained content container or layout contract to
  `TunnelEditorView` and `SettingsView`, which currently duplicate the relevant
  scroll/padding pattern.
- Add an Edit Profile visual fixture with representative saved values and the
  Name field focused plus a Settings fixture; retain New Profile and scrolled
  rule-editor coverage.
- Add a layout regression assertion that the rendered scroll content does not
  exceed its horizontal viewport while a text field is focused.
- Verify both modes with short and long content, representative focus state,
  vertical scrolling, light/dark appearance, rendered containment assertions,
  and a structurally verified macOS 13 deployment target.
- Replace the generic browser/smartphone prompts in the GitHub bug template
  with RelayBar version, macOS version, Mac architecture, and installation
  method fields.
- Update the application-shell system spec and verification evidence.

## Acceptance

- Opening an existing profile keeps section labels, fields, and rule cards at
  least 16 points from both popover edges; focusing or selecting Name does not
  shift or clip the form horizontally.
- New Profile, Edit Profile, and scrolled forwarding-rule states have no
  horizontal scrollbar or offscreen content at 380 × 440 points.
- Settings uses the same width constraint and remains horizontally stable when
  a control is focused, a caption appears, or vertical scrolling is required.
- Header and action-bar alignment is unchanged, all existing controls remain
  reachable, and saving or cancelling behaves as before.
- Light/dark visual evidence covers both editor modes, including the reported
  edit-state focus path, and shows balanced insets.
- The bug template requests RelayBar and relevant Mac environment details and
  contains no browser or smartphone questionnaire.
- Focused tests, strict tests, a warnings-as-errors Release build,
  `git diff --check`, and affected system-spec updates pass before completion.
