# RelayBar — Analysis & Backlog (ANALYSIS.md)

This is the consolidated, shovel-ready backlog derived from a full product and code
review of RelayBar (the original review text lives in `glm.md` on the
`comprehensive-review-ssh-tunnel` branch; a parallel audit exists in `sol.md`, PR #11).
Entries already implemented or in flight are recorded in the first two sections and
must not be picked up again. Everything else is ready for an implementer with a Mac:
each entry names the file(s) involved and the shape of the fix.

## Before picking up work

- Fetch remotes and check open PRs first — several backlog items have been landed or
  opened by parallel agents since this list was written.
- Follow the repo conventions: implementation happens on a feature branch, a task spec
  goes in `docs/task-specs/` (next free numbers start at `041`), system specs under
  `docs/system-specs/` are updated as part of the change, and every acceptance check
  needs evidence in `docs/verification/`.
- `swift test` requires macOS. CI runs it with `-warnings-as-errors`, so new warnings
  fail the build. Changed files can at least be syntax-checked anywhere with
  `swiftc -parse`.

## Landed (do not redo)

- **Edit restart** — editing a running profile now relaunches it with the replaced
  definition; the editor's save button reads **Save & Restart** while the profile owns
  lifecycle work (PR #6; a competing implementation in PR #7 was closed).
- **Delete confirmation, status-item tooltip/accessibility count, `~/.ssh/config`
  mtime+size caching, corrupt-`savedTunnels.v2` quarantine under
  `savedTunnels.v2.corrupt-backup`, 30-second control-socket readiness window**
  (all in PR #4).

## In flight (check status before starting)

- **Live retry countdown in the row** — PR #12 (`codex/retry-countdown`).
- **Duplicate profile** row-menu action — PR #10 (`codex/duplicate-profile`).
- **Back from a direct file opens its containing folder** — PR #8
  (`codex/back-to-parent-directory`); this removes the file-entry dead-end but does
  *not* add symlink traversal, which remains open below.
- **`sol.md` audit document** — PR #11; when it merges, consolidate any of its
  findings not covered here rather than duplicating them.

---

## Bugs & correctness

### B4. Remote symlinked directories open as a single dead-end row
`SFTPListingParser.directFileEntry` / `RemoteFilesModel.commitLoadedFile`.
A path that is a symlink to a directory lists one `symbolicLink` row (the parser
discards the `" -> target"` text); activating it downloads the link instead of
navigating, and there is no way forward. Same problem for symlink rows inside normal
listings — double-click should navigate.
**Fix sketch:** keep the link target on the entry (the raw `ls -la` text has it), let
`activate` follow directory-looking links, and re-list on the *resolved* path so the
path bar stays truthful. Tests: fixture listing with `name -> dir/` entries.

### B6. Remote Files server list goes stale while its window is open
`RemoteFilesWindowController.show` only pushes tunnels into the model when the user
re-clicks "Remote Files…". Add/delete of a profile with the window visible leaves the
picker stale.
**Fix sketch:** observe `TunnelStore.shared.$tunnels` (Combine) in the controller and
forward through `model.updateTunnels(_:)`, which already exists and handles selection
preservation.

### B7. Permanent SSH failures retry pointlessly
`TunnelStore.scheduleRetry` retries every exit 10 times with exponential backoff.
"Permission denied (publickey…)" under BatchMode, "Address already in use", "Could not
resolve hostname", and "Host key verification failed" are permanent.
**Fix sketch:** classify `errorMessage(for:)` output into a permanent set that skips
straight to `.failed` with a non-retriable message. The fake-SSH fixture already
supports injecting exit codes/messages, so tests are straightforward. Pair with B8.

### B8. Cross-profile listener conflicts surface only as runtime failure
`Tunnel.isSafeToRun.hasConflictingListeners` checks conflicts within one profile only.
Two profiles binding the same local port collide at runtime and today burn B7's retry
loop first.
**Fix sketch:** on `start`, check other *desired-active* profiles for overlapping
local TCP/Unix listeners and fail fast with "Another profile already listens on …".
Optionally probe with a bind test for non-RelayBar occupants of the port.

### B9. Quit with live tunnels has no consent moment
`TunnelStore.quit()` stops every tunnel instantly; the update flow carefully asks
first. Add a one-line confirmation ("Stop 3 active tunnels and quit?") — matches
interface principle 2. Careful: `applicationShouldTerminate` interplay and ⌘Q from the
main menu both funnel here; keep the prompt to the explicit footer Quit button at
first.

### B11. Hover-only group action menus
`TunnelGroupHeader` keeps its ellipsis menu at `opacity 0.001` until hover, which is
also a keyboard-discoverability problem. Prefer always-visible-but-quiet
(`foregroundStyle(.tertiary)`), or reveal on focus as well as hover.

### B12. Double selection paint in Remote Files `List`
`fileList` binds `List(selection:)` *and* paints its own accent row background; pick
one mechanism. Needs visual verification on current macOS.

### G1. Silent `try?` around persistence
`TunnelStore.save()` and the init decoders swallow errors (B2's quarantine in PR #4
covers the worst case). At minimum `NSLog` encode/decode failures so support can see
them in Console.

## Performance notes (already good; context for future work)

- The popover was tuned upstream: grouping cache invalidated per mutation, one shared
  `ByteCountFormatter`, `LazyVStack` lists, cheap highlight-cache keys.
- Directory-download progress re-walks the partial tree each poll but scales its
  interval 250 ms → 8 s with entry count; acceptable unless large-tree downloads
  become common.
- Remote Files `List` rows and the preview sidebar are already lazy.
- PR #4 removed the per-navigation `~/.ssh/config` re-read.

## Missing features — tunnel management

- **F1. Search/filter the profile list.** One field matching name, host, group, ports;
  becomes essential around ~10 profiles. Keep it in the header, keyboard-reachable.
- **F3. Drag to reorder** within the ungrouped section (groups are sorted;
  ungrouped order is insertion order with no user control). `Tunnel` order persists
  in the array already, so this is list plumbing plus `move` on the store.
- **F4. Import/export profiles as JSON.** Machine migration and backup; pairs
  naturally with the Quick Add parser. Export needs the same argument-safety review
  on import.
- **F5. Per-profile auto-start on launch.** "Connect my work tunnels at login"
  without touching every row; pairs with Launch-at-Login. Store a per-profile flag;
  on launch, start flagged profiles after the store loads.
- **F6. Per-profile retry policy** or a global "pause retries" toggle; attempts and
  backoff are hard-coded (10 attempts, cap 60 s).
- **F7. Connection uptime + failure count per row** (or row detail popover).
  "Up 3h 12m · restarted 4×" needs only a launch timestamp next to each phase.
- **F8. Opt-in notification on permanent failure / give-up** (off by default; respect
  the "consent licenses the interruption" principle).
- **F9. Global hotkey to open the popover** (Carbon `RegisterEventHotKey`, no
  accessibility permission needed). Settings row with recorder UI.
- **F10. `relaybar://` URL scheme for one-click profile import** from wikis/readmes;
  validate through the same `SSHCommandParser` path as Quick Add.
- **F11. Per-rule enable/disable toggle** — suspend a rule without deleting it.
  `ForwardingRule` gains a `isEnabled` field (default true); disabled rules are
  skipped in `installRules` and shown struck-through in the editor.

## Missing features — editor

- **F12. Validation messages.** Save is silently disabled; show the first blocking
  issue ("Rule 2's port must be 1–65535", "Rules 1 and 3 listen on the same port",
  "Choose a Remote SOCKS destination policy"). `builtTunnel` already computes
  validity; surface the reason instead of just the boolean.
- **F13. Jump-host and identity affordances.** `-J`/`-i` today only arrive via
  import; a validated "Jump host" field would be friendlier than "additional
  arguments".
- **F14. Batch Quick Add** — one `ssh` command per line, one profile each; report
  per-line failures.

## Missing features — Remote Files

- **F15. Clickable breadcrumb path bar.** The centered monospaced path is begging to
  be segmented; click a segment to jump (each hop is a cached or cacheable listing).
- **F16. Type-ahead folder filter** (Finder-style); instant on cached listings.
- **F17. Sort control + hidden-files toggle** (dotfiles are always shown; some
  folders are 80% dotfiles).
- **F18. Multi-select downloads + transfer queue.** One transfer at a time today;
  a second Download click while active is ignored. Selection model exists
  (`selectedEntryID`); needs `Set` and a serialized queue.
- **F19. Per-server recent paths.** Remember the last N paths per connection
  identity; "reopen /srv/app/output" is the most repeated action. Mirror the
  `recentServers.v1` pattern as `recentPaths.v1` (bounded, per-connection).
- **F20. Richer previews: PDF, plain text, JSON, CSV.** The bounded-download +
  decode infrastructure for images/markdown already exists.
- **F21. Upload (opt-in, off by default, drag-drop).** Turns Remote Files into a
  real tool; needs a careful security story (staging, overwrite confirmation,
  `put` instead of `get`, same argument policy).
- **F22. "Reveal in Finder when download completes" preference.**
- **F24. Window title shows the current path** for Mission Control/⌘Tab context.

## Missing features — system integration

- **F25. VoiceOver announcements on tunnel state transitions** (groundwork exists —
  `SystemAccessibilityAnnouncer`).
- **F26. Menu-bar count badge / per-state icon variants** (see D2).

## Visual & layout

- **V1. Design tokens.** Corner radii mix 13/12/10/7; labels mix 9.5pt tracked caps
  and 10.5pt sentence case; paddings mix 11/12/14. Pick a scale (e.g. radius 10/14,
  label 10pt/0.5 tracking) and apply — reads "designed" rather than "assembled".
- **V2. Four-segment rule-kind `Picker`** truncates inside 380 pt; shorten labels
  ("Local", "SOCKS", "Remote", "Remote SOCKS") or switch to a menu picker.
- **V3. Fixed-point typography** forfeits Dynamic-Type accessibility scaling; a
  future pass could map to text styles.
- **V4. Flat popover background** — a `.regularMaterial`-backed popover would read
  more "system high-value"; verify contrast in both appearances.
- **V5. Status indicator pulse** while `.starting`/`.retrying` (opacity-only
  animation on the 8 pt dot).
- **V6. Clipboard-aware empty state** — "We noticed an SSH command on your clipboard
  — import it?" when the clipboard plausibly starts with `ssh ` (see D3).
- **V8.** Same hover-reveal issue as B11.

## Convenience & speed

- **U2. Keyboard flow in the list:** ⌘N new profile, ↑/↓ move, Space/Enter toggle,
  ⌘F search, ⌘1…9 toggle the first nine.
- **U3. "Copy URL" on the row** for one-rule profiles (the ellipsis menu has Copy
  endpoints per rule already; surface the common case).
- **U4. Restore per-screen focus** when the popover reopens (navigation state is
  already kept; focus is not).
- **U5. Let Edit re-import a Quick Add command** (replace rules; power users keep
  their commands in notes).
- **U7.** Covered by F19.

## Aesthetics

- **A1.** Matching monochrome/duotone brand treatment in Settings' About footer.
- **A2.** Unify card surfaces: rows use `controlBackgroundColor`, editor panels use
  `Color.primary.opacity(0.035)` — pick one.
- **A3.** Reuse the play/stop circle-chip visual language for the row's safari and
  ellipsis actions so the row reads as one family.
- **A4.** Gentle push transition between list → editor → settings (0.15 s) instead
  of hard cuts.
- **A5.** Empty-state artwork in the two-arrows brand motif (currently a network
  triangle symbol).
- **A6.** Opt-in "dashed" menubar variant while any profile is connecting.

## Engineering hygiene

- **G2.** `RemoteFilesModel` is a ~900-line god object (navigation, cache, preview,
  transfer, catalog). Split Transfer and Preview into child models before F18/F20.
- **G3.** Introduce the V1 design-token enum as part of any visual pass.
- **G4.** Extract a pure `masterArguments(tunnel:controlSocket:)` accessor if D1 is
  taken (it's currently private).

## Delightful / quirky (all opt-in)

- **D1. "The exact command" panel** in the editor — a collapsible footer showing the
  literal `ssh -N -T -M -S …` line the app will run, generated by the same code that
  runs it. Transparency is trust.
- **D2. Living menubar icon** — one-time "ping" animation when a tunnel comes up;
  opt-in count badge for multi-tunnel users.
- **D3.** See V6.
- **D4. Per-tunnel connection log sheet.** The store already buffers the master's
  stderr (16 KiB bounded). "View Log" surfaces auth problems ("Offered public key…
  rejected") that today compress into one red line. Nearly free, uniquely honest.
- **D5. Soft sound on connect after a retry** (opt-in, off).
- **D6. ⌘K quick switcher** — fuzzy search profiles *and* recent remote paths.
- **D7. Panic stop** — ⌥-click the menubar icon stops every tunnel
  (airport-security moment).
- **D8. Per-row forwarded-port heartbeat** (one TCP connect per N seconds, opt-in)
  — turns the row into a living status board.
- **D9. Group "Start All" summary toast** — "Work: 3 up, 1 failed — click for
  details" instead of scanning rows.
