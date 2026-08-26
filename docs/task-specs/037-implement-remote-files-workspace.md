# Task 037 — Implement Remote Files Workspace

Status: In Progress

Created: 2026-08-24

## Outcome

Implement the approved Task 036 design and turn Remote Files into a stable,
native workspace that makes frequently used
remote folders reachable with one deliberate pointer click or accessibility
activation. Replace the compact launcher and browser mode switch with one
resizable window: recent folders and recent hosts remain available in a leading
sidebar, while the selected folder, preview, transfer, or quiet empty state uses
the larger detail pane.

Add explicit file upload from the current remote folder without expanding
RelayBar into a sync client or general remote-file editor.

## Delivery Boundary

### Included

- One persistent Remote Files split workspace with a hideable leading location
  sidebar and a flexible detail pane.
- Bounded, locally persisted recent folder locations, shown globally and under
  their recent SSH hosts.
- A single **Add Path…** flow that retains the current exact-host and
  exact-absolute-path connection model.
- Upload of one local regular file at a time into the currently open remote
  folder, with explicit conflict handling, progress, cancellation, and bounded
  cleanup.
- Preservation of current folder navigation, previews, downloads, SSH session
  reuse, accessibility, and security limits.
- Updated product, privacy, system-spec, and verification documentation after
  implementation.

### Excluded

- Search, indexing, workspace discovery, mounting, synchronization, background
  reconnection, or automatic opening of a network connection when the window
  appears.
- Remote text editing, rename, move, delete, permission changes, or arbitrary
  remote commands.
- Multi-file selection, folder upload, drag and drop, upload resumption,
  background transfer queues, or transfers across multiple hosts at once.
- A recursive remote tree or persistence of remote directory listings or file
  contents.
- Commit, push, release, notarization, publication, or deployment.

## Proposed Interface

![Remote Files workspace welcome, folder, add-path, upload, and preview states](../designs/media/036/remote-files-workspace.png)

- **Recent Folders** shows the most recently opened host-and-path pairs. Each
  row identifies both the folder and host. A pointer click, Return on the
  focused row, or an accessibility press starts the open; focus traversal and
  arrow-key movement alone never initiate SSH.
- **Recent Hosts** shows the existing bounded recent-host catalog. Expanding a
  host reveals recent paths that are not already visible in the global section,
  avoiding duplicate active rows without implying a default home directory.
- **Add Path…** opens a focused sheet with the complete existing host
  catalog and one absolute-path field. **Add SSH Host…** remains available for
  people whose host is not represented by a profile or OpenSSH alias.
- The detail pane starts quiet and empty. Opening the window alone performs no
  SSH work; selecting a recent location or choosing **Open** in the sheet is
  the action that connects.
- The browser toolbar keeps navigation and refresh at the leading edge and adds
  one trailing **Upload…** action. Transfer feedback stays adjacent to the
  folder contents instead of becoming a separate workflow.
- Preview remains inside the detail pane. Its current previewable-sibling list
  becomes the first, contextual **In This Folder** section in the same leading
  sidebar, above Recent Folders and Recent Hosts, so the redesign has one
  sidebar and one visibility command rather than nested sidebars.

## Work

### 1. Replace the launcher with one workspace shell

- Open Remote Files directly at a 920 × 600 point resizable window and keep a
  native leading sidebar present across the welcome, folder, preview, loading,
  error, and transfer states. Use a 760 × 440 minimum, with a 210 point minimum,
  250 point ideal, and 360 point maximum sidebar and at least 430 points for the
  detail. Preserve the current grow-only 980 × 640 preview preference.
- Use one split-layout owner and stable selection model. A sidebar location
  activation opens in the detail pane; Back operates on detail-pane navigation
  history without changing the saved ordering of sidebar items. Forward
  navigation remains deferred.
- Treat rows as activatable source-list items rather than connection-triggering
  selection bindings. Pointer click, Return, and the accessibility press action
  activate; arrow keys and VoiceOver traversal only move focus. After a
  successful open, keep the activated location marked as the workspace root
  while the detail navigates through descendants. Do not infer a different root
  because the current subfolder happens to match another recent row.
- In the browser, the activated workspace-root row uses the source-list accent.
  During preview, the active sibling owns selection accent and the workspace
  root retains a non-selection root marker and accessibility description. The
  welcome state has no active or selected location.
- Preserve a useful detail width at the minimum window size. Provide a standard
  accessible sidebar toggle and keyboard shortcut. Do not duplicate the
  current preview-sidebar toggle; fold previewable siblings into a contextual
  **In This Folder** section. While focus is in the sidebar, arrows navigate the
  list and disclosures and Return activates; while focus is in the preview
  detail or the sidebar is hidden, Left/Right switches previewable siblings.
- Keep Recent Folders and Recent Hosts available during preview. Activating a
  location closes the preview and opens that location unless a transfer is
  active. While an upload or download is active or cleaning up, disable every
  location activation, Back-to-welcome, and server change just as current Back
  navigation is disabled.
- Preserve the selected location and sidebar expansion state while the window
  remains open. Closing the window still ends the active SSH session, clears
  directory snapshots and preview content, and cancels active operations.
- Back from the first opened folder returns to the quiet welcome detail, clears
  the active location, and performs the current launcher-return teardown: end
  the SSH session and clear directory snapshots and preview content. Merely
  focusing a different sidebar row does not tear down or connect anything.

### 2. Persist bounded recent locations

- Add a versioned recent-location record containing only the normalized
  absolute path, exact SSH connection identity, display metadata needed to
  resolve the host, and recency order. Do not persist listings, file names from
  a listing, file contents, credentials, or connection state.
- Record a location only after a successful folder or direct-file open. Collapse
  duplicates by exact connection identity and normalized path, move a reopened
  location to the front, cap the global collection at 16, and show at most six
  global rows plus three nested paths per recent host before an overflow
  affordance.
- A direct-file open records its normalized parent folder in Recent Folders,
  not the file path. Reopening that recent folder does not automatically reopen
  or download the former file.
- Omit from each host's nested rows any location already visible in the global
  Recent Folders section. **Show All Paths…** exposes the remaining bounded
  history for that host; **Show All Recent Folders…** exposes global rows beyond
  six. A host's count describes its total bounded history, including paths
  currently represented in the global section. The underlying recency
  collection is shared, not duplicated.
- Keep the existing eight-host recent limit and complete host picker. Removing
  a standalone host also removes its matching recent host and location records
  without changing forwarding profiles or OpenSSH config.
- Treat failed, cancelled, or superseded opens as non-events for recency. A
  failed recent-location open leaves the entry in its prior position and shows
  a detail-pane error with **Retry** and **Remove from Recents**; it never
  becomes a source of automatic retry.
- Update the privacy disclosure because exact remote paths will change from
  session-only state to bounded local history. Each recent row's context menu
  includes **Remove from Recents**. A Recent Folders section menu includes
  confirmed **Clear Recent Locations…**, which clears global and host-nested
  path history without removing hosts.
- With no recent locations or hosts, omit empty section chrome, keep the quiet
  guidance in the detail, and present one prominent **Add Path…** action.

### 3. Make adding an unfamiliar path direct

- Replace the launcher's persistent form with **Add Path…** in both the
  sidebar header and the empty detail state.
- The sheet contains the complete deduplicated host catalog, the current
  **Add SSH Host…** affordance beside the host picker, one absolute remote-path
  field, validation, and a default **Open** action. The sidebar does not duplicate
  **Add SSH Host…**. The sheet does not save a location until the open succeeds.
- When invoked from a recent host, preselect that host. Otherwise prefer the
  active host, then the newest recent host, while keeping the choice explicit
  and editable.
- Keep the last entered values in the sheet after a connection or path error so
  retry does not require re-entry.

### 4. Add explicit, failure-safe file upload

- Enable **Upload…** only for a successfully opened folder and while no other
  upload or download is active. Use a native local file picker that accepts one
  regular file and rejects folders, aliases that cannot be resolved to a regular
  file, sockets, devices, and other unsupported objects.
- Refresh or otherwise revalidate the target name before transfer. A regular-file
  collision requires a prompt naming that file and an explicit **Replace**
  decision. Refuse an observed directory or symbolic-link conflict.
- Run one bounded, app-owned SFTP capability probe per active SSH session. Add
  app-controlled debug-level-2 (`-vv`) output after validated user arguments,
  retain the same 1 MiB diagnostic cap, parse only exact server extension
  advertisements, and never persist or log the surrounding diagnostics. Cache
  whether the server advertises `hardlink@openssh.com` and
  `posix-rename@openssh.com` for that session; treat missing or unparseable
  advertisement output as unsupported and never infer support from server
  brand or version.
- Upload the file through the active owned SSH master to a unique hidden
  staging name in the target directory. Publish the final name only after the
  complete bytes arrive.
- For a name that did not exist at consent time, require the hard-link extension:
  create the final name as a hard link to the staging file, which fails if a
  target appeared concurrently, then remove the staging name. If the extension
  is absent or the link reports a collision, leave the target unchanged, remove
  staging, and fail with a truthful unsupported-or-conflict message.
- For a regular file the user explicitly approved replacing, require the POSIX
  rename extension and use its atomic overwrite from the same-directory staging
  name. Revalidate that the connection, folder, and target name still match the
  approved operation immediately before publish. If the extension is absent or
  the target has become a directory or symbolic link, fail closed before
  publication and leave the existing target unchanged.
- Treat replace consent as applying to the named directory entry after the final
  revalidation, not to an immutable remote inode. SFTP has no compare-and-swap
  primitive, so another actor can change that entry in the final race window.
  POSIX rename replaces a raced-in symbolic-link entry itself and never follows
  its target; a file-over-directory rename fails. Document this residual race in
  the confirmation and live-SSH evidence rather than promising impossible
  cross-client exclusion.
- Keep the current one-transfer-at-a-time invariant. Cancellation stops the
  active child, removes its exact staging file, and reports cleanup truthfully.
- On failure or cancellation, make a bounded attempt to remove RelayBar's exact
  staging paths and report if cleanup could not be confirmed. Never use a shell,
  wildcard cleanup, recursive delete, or an unverified path.
- Refresh the presented folder after each completed final rename without
  blanking valid rows. Generation guards must prevent delayed progress or
  refresh results from mutating a newer location or transfer.
- Apply existing host/path validation, SSH argument policy, batch quoting,
  output caps, process ownership, cancellation, and window-close cleanup to
  uploads. Add bounded local-file size/progress reads and remote-path length
  checks before starting SFTP.
- Use indeterminate upload progress in v1: show the local filename, a busy
  indicator, **Cancel**, and the staging/publishing phase. Do not parse SFTP's
  terminal progress meter or launch polling children solely to invent a byte
  percentage. Completion remains exact.

### 5. Verify the redesigned flow

- Add deterministic catalog/model coverage for ordering, deduplication, caps,
  host removal, clearing history, failed opens, stale paths, selection, sidebar
  visibility, navigation history, and migration from current preferences.
- Add upload service and lifecycle coverage for capability parsing, new files,
  explicit replacement, conflict races, unsupported targets and extensions,
  staging, hard-link publication, POSIX rename, cancellation, cleanup failure,
  master loss, late callbacks, and window close.
- Capture welcome, populated folder, expanded recent host, add-path validation,
  preview, upload progress, conflict, failure, empty-history, long-path, narrow,
  Aqua, Dark Aqua, keyboard-focus, and larger-text states.
- Exercise the complete open, revisit, preview, download, upload, cancel, retry,
  history removal, and close flow against a real SSH server. Record whether the
  server supports the replacement guarantee and prove the failure-closed path
  when it does not.

## Design Review

A read-only Claude Fable CLI review on 2026-08-20 approved the workspace
direction but withheld approval of the first draft until three gaps were closed:
selection could not implicitly connect during keyboard or VoiceOver traversal;
upload replacement needed a concrete, race-aware SFTP capability contract; and
the welcome/session teardown plus unified preview sidebar needed defined states.

Accepted into this revision:

- separate safe focus traversal from pointer, Return, and accessibility
  activation; block location changes throughout an active transfer;
- define Back-to-welcome as the replacement for launcher-return teardown;
- add the preview mock and specify one contextual sidebar, focus-dependent arrow
  ownership, and continued recent-location access;
- remove duplicate global/nested recent rows, define direct-file recency, stale
  errors, overflow, first-run, remove-one, and clear-all surfaces;
- remove Forward and multi-file upload from this delivery boundary;
- make upload progress indeterminate and define exact hard-link/POSIX-rename
  capability detection and race behavior;
- align **Add Path…**, host addition, disabled upload, layout bounds, and sheet
  validation across the mock and contract.

Kept unchanged at Fable's recommendation: no connection on window open, exact
host and absolute-path input, one transfer at a time, same-directory hidden
staging, complete existing transport limits, and the exclusions for search,
mounting, sync, editing, and background reconnect.

Deliberately deferred: pinned locations, drag-and-drop, Forward, multi-file and
folder upload, resumption, and multi-host transfer. These may become separate
tasks after usage evidence; they are not implicit follow-up work for Task 037.

A follow-up Fable review on 2026-08-20 confirmed that all three blocking issues
and every P1 recommendation were resolved and approved this boundary. Its five
nonblocking polish notes were also incorporated: honest indeterminate progress,
total host-path counts, explicit root-selection appearance, debug-level-2 probe
parsing, and a truthful residual replacement-race statement.

A final read-only Fable implementation review on 2026-08-24 approved the
implemented Task 037 boundary with no remaining Blocker or P1 finding. Its last
P1 was resolved by binding upload and download retry cards to their originating
connection and normalized directory, clearing finished cards on navigation,
and refusing a retry after the active location changes. Required live-server
workflow evidence remains pending and is tracked separately from that approval.

## Acceptance

- Selecting **Remote Files…** opens one stable split workspace. With recent
  history present, a common folder requires one additional pointer click and no
  path or host re-entry. Focus or accessibility traversal alone never connects;
  Return and accessibility press remain explicit activations.
- Opening the window performs no SSH operation. Activating a recent location or
  choosing **Open** in **Add Path…** is the explicit connection action.
- The sidebar visibly separates recent folders from recent hosts, nests bounded
  nonduplicated recent paths beneath hosts, preserves access to the complete
  current host catalog, and remains usable with long localized labels and paths.
- Successful opens persist and reorder exact host-and-path pairs within the
  defined bounds. Failed or cancelled opens do not. Individual removal, clear
  history, standalone-host removal, and preference migration preserve unrelated
  hosts, forwarding profiles, and OpenSSH config.
- Folder navigation, cached Back/revisit, refresh, direct-file opening, image
  and Markdown preview, preview sibling switching, downloads, errors, and
  window cleanup retain their current behavior inside the new shell.
- Back from the first folder returns to welcome and retires the session. Preview
  shows **In This Folder** above recents in the single sidebar; sidebar-focused
  arrows never trigger preview switching, and detail-focused Left/Right retains
  it.
- **Upload…** is available only in an open folder. New files appear after safe
  hard-link publication; regular-file conflicts require explicit consent and
  POSIX-rename support; RelayBar never knowingly replaces an observed directory
  or symbolic link; absent extensions and new-name conflicts fail without
  changing the target; approved replacement discloses the bounded final race.
- Upload cancellation, failure, connection loss, navigation supersession, and
  window close leave no locally owned process or known remote staging path
  behind when cleanup is confirmable and report completion or unconfirmed
  cleanup truthfully.
- Sidebar, add-path, conflict, transfer, error, and preview interactions have
  coherent VoiceOver labels, keyboard order, focus restoration, contrast, and
  minimum-window behavior in Aqua and Dark Aqua.
- Relevant focused and complete tests, warnings-as-errors Release build,
  `git diff --check`, visual review, privacy review, and live-SSH verification
  pass. A fresh Fable review has no unresolved issue within the approved
  boundary.
- Affected system specs and product/privacy documentation describe the shipped
  persistence, workspace, upload, safety, and cleanup behavior before this task
  is marked Complete and archived.
- No commit, push, release, notarization, publication, or deployment occurs
  without separate explicit approval.

## Completion Artifacts

- Remote Files source and focused tests.
- `docs/system-specs/modules/remote-files.md`
- `docs/system-specs/shared/data-and-state.md`
- `docs/system-specs/shared/security-boundaries.md`
- `docs/system-specs/operations/verification.md`
- `docs/designs/remote-files.md`
- `docs/designs/media/036/remote-files-workspace.png`
- `PRIVACY.md` and user-facing Remote Files documentation.
- `docs/verification/037-remote-files-workspace.md`
