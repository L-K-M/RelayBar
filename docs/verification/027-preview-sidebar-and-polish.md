# Task 027 Verification

Date: 2026-07-30

Result: Pass. Implementation, automated checks, screenshots, independent
review, and native accessibility interaction all pass.

## Automated checks

- `swift test -j 1 --no-parallel -Xswiftc -warnings-as-errors` passed 205
  tests with 15 expected opt-in tests skipped and no failures.
- Model coverage verifies that the previewable sibling set excludes folders
  and unsupported files; keyboard movement cancels a pending sibling,
  publishes only the latest content, removes the superseded preview directory,
  restores the latest row selection, and performs no second listing.
- Window sizing coverage verifies that the default 780 × 520 browser grows to
  980 × 640 for preview and a user-enlarged window is never shrunk.
- The focused Markdown and preview tests passed with warnings as errors.
- Keyboard helper coverage verifies that macOS's `.numericPad` and `.function`
  flags on ordinary arrow events do not make them appear modified, while real
  Shift or Command combinations remain excluded.
- The unsigned arm64 Xcode Release build passed. The RelayBar target retains
  complete strict concurrency and warnings-as-errors in the project settings.
  A discarded invocation that forced that setting onto every package target
  failed because three dependencies intentionally combine suppressed warnings
  with their own settings; the canonical build without that global override
  passed.

## Visual evidence

`VisualSnapshotHarness/testCaptureTask027Snapshots` passed and generated six
captures:

- image preview with sidebar in Aqua and Dark Aqua;
- Markdown preview with sidebar in Aqua and Dark Aqua;
- focused Markdown with the sidebar hidden in Aqua and Dark Aqua.

The final 980 × 640 and 780 × 520 point captures were inspected from
`/tmp/RelayBarTask027Snapshots.cZeuTD`. They show:

- a compact adaptive sidebar, readable selected row, file type, timestamp,
  size, and current-folder context;
- a quiet intrinsic-size image canvas in both appearances;
- a centered 680-point Markdown measure with the inherited fixed text-run
  backgrounds removed;
- the leading sidebar control, **All Files**, two-line file title, and one
  restrained trailing **Download** action;
- a clean focused state with no stranded divider or sidebar space.

The PNGs are reproducible temporary verification output, not repository
assets.

## Claude Fable CLI review

The requested read-only Claude Fable CLI review inspected the spec, source,
and all six screenshots. It approved the interaction model, image canvas,
toolbar hierarchy, row metadata, local detail feedback, and grow-only window
sizing, then identified several polish issues.

Accepted and implemented:

- removed MarkdownUI's inherited fixed GitHub text background, eliminating
  light and dark prose bands while retaining intentional callout surfaces;
- reduced the Markdown reading measure from 860 to 680 points and increased
  bottom breathing room;
- kept sibling switching available when the sidebar is hidden and moved it to
  Left/Right so vertical arrows remain available for document scrolling;
- moved the sidebar toggle to the far leading edge, changed it to the
  leading-edge symbol, added Control-Command-S, and animated visibility;
- gave the bare sibling count a descriptive accessibility label.

Deliberately deferred:

- migrating the entire Remote Files window to `NSToolbar` plus a full-height
  AppKit or `NavigationSplitView` sidebar would also redesign the launcher and
  folder browser chrome, beyond this preview-focused task;
- replacing the custom compact rows with `List(selection:)` was not adopted
  after the snapshot harness exposed illegible inactive system selection
  rendering. The shipped rows instead retain explicit accent selection,
  button semantics, selected traits, labels, hints, and a global
  preview-scoped Left/Right interaction.

## Native accessibility interaction

An isolated current-source Debug `.app` exercised the real SwiftUI/AppKit
window and deterministic Remote Files fixture:

- double-clicking `dashboard.png` opened the image workspace; clicking
  `README.md` changed the selected row, toolbar title, metadata, and detail;
- Left and Right moved between both siblings with the sidebar shown and with
  it hidden;
- Control-Command-S hid and restored the sidebar, and the native split value
  changed from 210 to 300 points while leaving the detail usable;
- Escape returned from `README.md` with that browser row selected, and
  Command-Left-Bracket returned from `dashboard.png` with its row selected;
- the accessibility tree exposed the sidebar toggle's changing label, the
  `All Files` and `Download` controls, row button semantics, selected traits,
  file type, timestamp, size, help, Markdown headings, and image description.

The first native arrow pass exposed two routing defects that automated model
coverage could not reveal: arrow events may use the key window while reporting
no event window, and ordinary macOS arrows carry both `.numericPad` and
`.function`. The monitor now accepts the key-window route, ignores only active
document text views rather than the launcher's stale field editor, and treats
the system arrow flags as unmodified. The rebuilt fixture passed the complete
sequence, and the regression helper tests pass.

## Post-acceptance deployment

After separate explicit user approval on 2026-07-30:

- the current working tree produced universal RelayBar 1.3.0 build 5 with
  matching x86_64 and arm64 executable/dSYM UUIDs;
- Developer ID Application `Thought Tides LLC (39HYFR5Z65)` signed the
  hardened-runtime bundle;
- Apple accepted notary submission
  `35c72426-cbde-493d-ab89-f2224213d7e1`, and the ticket was stapled and
  validated;
- Gatekeeper reported `source=Notarized Developer ID`, and the notarized ZIP
  SHA-256 is
  `e8b9c67d5e3deeba3b14237c070dab8d078bb44cb302613628d2002dc49b600e`;
- `/Applications/RelayBar.app` was replaced with the verified bundle and
  relaunched. The prior installation remains recoverable at
  `~/Library/Application Support/RelayBar/Deployment Backups/RelayBar-pre-task027-20260730.rollback`.

No commit, push, public release, appcast publication, or Homebrew publication
was performed.
