# Task 027 — Preview Sidebar and Polish

Status: Complete

Created: 2026-07-30

Accepted: 2026-07-30

## Outcome

Make image and Markdown preview feel like a native Mac workspace instead of a
full-window dead end. Keep the current folder's previewable files in a
resizable leading sidebar so people can move between related content without
returning to the browser, while preserving a spacious, quiet detail view.

Follow Apple's guidance for
[sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
and [Mac layout](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/):
use familiar structure, system appearance, flexible window sizing, and
keyboard access instead of ornamental custom chrome.

## Delivery Boundary

### Included

- A resizable, hideable leading sidebar during image and Markdown preview.
- Fast switching among previewable siblings from the already loaded folder.
- A calmer preview toolbar, image canvas, Markdown reading width, spacing,
  selection treatment, and responsive window sizing.
- Preserved preview cancellation, temporary-file cleanup, download, Back,
  Escape, and keyboard behavior.
- Light and dark screenshots at representative sizes, accessibility and
  interaction checks, and a requested Claude Fable CLI design review.

### Excluded

- A recursive folder tree, search, thumbnails, Quick Look integration,
  metadata inspection, editing, markup, or a persistent content cache.
- Prefetching every sibling, downloading unselected files, or changing Remote
  Files' read-only and exact-path boundaries.
- Publication, notarization, installation, or other deployment.

## Work

### 1. Keep context beside the preview

- Replace the full-window preview takeover with a native split layout: a
  leading contents pane and a detail pane separated by a draggable divider.
- Populate the sidebar only from previewable image and Markdown entries in the
  current in-memory folder snapshot. Do not issue another directory listing.
- Keep the active preview row selected and visible. A click or keyboard
  selection of another row cancels superseded preview work and loads that
  sibling through the existing shared SSH session.
- Keep Escape and Command-Left-Bracket returning to the full browser with the
  same selected row. Provide a standard show/hide sidebar control and retain a
  useful detail area when the window is narrow.

### 2. Refine the visual hierarchy

- Give the sidebar a system material and compact native list treatment with
  file-type symbols, truncated names, restrained metadata, and the user's
  accent color for selection.
- Keep navigation and sidebar visibility at the leading edge, the active
  filename as the title, and Download at the trailing edge. Avoid fixed colors
  and oversized controls.
- Present images on a quiet adaptive canvas with enough breathing room and no
  upscaling beyond their decoded dimensions. Keep Markdown selectable,
  read-only, and constrained to a comfortable reading width.
- Grow a browser-sized window enough for the first split preview without
  shrinking a window the user already enlarged. Preserve resizability and set
  a minimum that keeps both panes usable.
- Keep loading, error, retry, and transfer feedback local to the detail view
  and visually stable while switching files.

### 3. Verify the complete interaction

- Add deterministic model and view coverage for sibling switching,
  superseded-load cleanup, selection restoration, sidebar visibility, and
  window sizing.
- Capture image and Markdown previews in Aqua and Dark Aqua, including an
  expanded sidebar and a focused collapsed-sidebar state.
- Inspect the screenshots for hierarchy, spacing, truncation, contrast,
  narrow-window behavior, and visual regressions.
- Ask Claude Fable through the CLI to critique the screenshots and interaction
  model, incorporate actionable feedback, and record accepted or rejected
  recommendations with rationale.

## Acceptance

- Image and Markdown previews show a draggable leading sidebar containing the
  current folder's previewable siblings, with the active file selected.
- Clicking a sibling or moving to it with the keyboard starts its preview
  immediately, cancels obsolete work, never publishes stale content, and
  leaves no superseded preview directory behind.
- Sidebar switching reuses the active Remote Files SSH master and performs no
  new listing, search, recursive discovery, or eager sibling download.
- The sidebar can be hidden and restored with an accessible native control;
  the detail remains useful at the minimum window size.
- Escape and Command-Left-Bracket return to the browser with the active
  preview file selected. Download, retry, transfer, and close cleanup continue
  to work.
- Entering preview grows only an undersized browser window; it does not shrink
  a user-resized window.
- Aqua and Dark Aqua screenshots for image, Markdown, and focused preview pass
  visual inspection and receive a documented Claude Fable CLI review.
- Relevant strict tests, the warnings-as-errors Release build, accessibility
  interaction checks, and `git diff --check` pass.
- Remote Files and window-lifecycle system specs describe the implemented
  layout, interaction, sizing, cleanup, and remaining boundaries before this
  task is marked Complete and archived.
- No commit, push, notarization, installation, publication, or deployment
  occurs without separate authorization.
