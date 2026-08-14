# RelayBar — Comprehensive Product & Code Review (glm.md)

Reviewed: full `Sources/RelayBar` (~14.7k lines), `Package.swift`, `Packaging/Info.plist`,
`Tests/RelayBarTests` (≈245 tests), scripts, system/task specs, and the GLM-5.3 PR-review
workflow. The reviewer's environment has no Swift toolchain, so everything below comes from
close reading; entries marked **[implement]** were re-verified line-by-line before coding.

## Overall assessment

This is a unusually well-engineered menubar app. The process management is careful
(generation-tagged control operations, inode-tracked socket ownership, SIGTERM→SIGKILL grace
windows, bounded output buffers), the security posture is serious (posix_spawn with
CLOEXEC, argument allowlists, symlink-safe staging downloads, template-image markdown),
and the repo has real spec discipline plus a broad test suite. The fork's status-item
ownership work (AppKit `NSStatusItem` with an autosave name) is correct and well-argued.

The weaknesses are mostly *product-level*: silent data-loss edges, a few static/lying UI
states, missing consent moments, a flat visual language that undersells the engineering,
and a long tail of small conveniences that separate a "tool" from a "delightful tool".

---

## 1. Bugs & correctness risks

### B1. Editing a running profile silently kills the connection — `TunnelStore.update`
`update()` stops an active tunnel when any non-tag field changes and leaves it stopped.
The user pressed "Save Changes", not "Disconnect". They lose their session, and nothing
tells them the tunnel is now down except the row's grey dot. **Fix:** restart the profile
with the new configuration after save (stop is bookkeeping-synchronous — `cleanupRuntime`
clears `processes[id]` before `stop()` returns — so an immediate `start(tunnel)` is safe).
Update the two integration tests that assert `.stopped` after an edit, and the spec.
**[implement — PR 2]**

### B2. Corrupt saved-profiles JSON silently wipes the user's data — `TunnelStore.init`
If `savedTunnels.v2` fails to decode (disk corruption, partial write, manual edit), the
store initializes empty and the *next* `save()` overwrites the blob. All profiles are gone
with zero feedback. **Fix:** when decode fails but data exists, quarantine the raw bytes
under a backup key (e.g. `savedTunnels.v2.corrupt-backup`) before continuing, so support
can recover it. **[implement — PR 1]**

### B3. Frozen retry countdown — `TunnelRow.errorOrHost` + `TunnelPhase.retrying`
The row shows "Retrying in 42s · …" but the phase never republishes during the wait, so
"42s" sits on screen for the full 42 seconds (up to 60s at max backoff). Either count down
for real (a `TimelineView(.periodic)` confined to retrying rows, with a deadline the store
exposes) or stop promising a live number. Low severity, but it makes the app look stuck
exactly when the user is most anxious. *(doc-only for now; keep the copy honest)*

### B4. Remote symlinked directories open as a single dead-end row — `SFTPListingParser.directFileEntry` / `RemoteFilesModel.commitLoadedFile`
Entering a path that is a symlink to a directory lists one `symbolicLink` row (the parser
discards the `" -> target"` text). Activate downloads the link instead of navigating it,
and there is no way forward. **Fix sketch:** keep the link target on the entry and let
`activate` follow directory-looking links (or resolve via `ls` on the target). Same issue
for symlink rows inside listings — double-click should navigate.

### B5. Control-socket readiness window is too tight for real auth — `TunnelStore.waitForControlSocket`
The poll loop caps at 240×50ms = 12s, while `ConnectTimeout=10` only bounds the TCP
connect. Slow WANs, GSSAPI, FIDO touch prompts on other agents, or large agent key rings
can push auth past 12s; the profile then reports "SSH connected but its private control
socket did not become ready" (which is misleading — it usually didn't finish
authenticating) and burns a retry cycle. **Fix:** raise the window to 30s (600 polls) and
reword the failure. **[implement — PR 1]**

### B6. Remote Files server list goes stale while its window is open — `RemoteFilesWindowController.show`
The model only learns about profile changes when the user clicks "Remote Files…" again.
Adding/deleting a profile with the window visible doesn't update the server picker until
re-open. **Fix sketch:** observe `TunnelStore.shared.$tunnels` (Combine) in the controller
and forward via `updateTunnels`.

### B7. Permanent SSH failures are retried pointlessly — `TunnelStore.scheduleRetry`
"Permission denied (publickey…)" under BatchMode, "Address already in use", "Could not
resolve hostname", and "Host key verification failed" are all permanent, yet each burns
10 retries with exponential backoff (≈5 minutes of Orange before the red "Issue" badge).
**Fix sketch:** classify these messages and transition straight to `.failed` with a
clear, non-retriable error. (Deferred — worth doing carefully with tests; the fake-SSH
fixture already supports injecting exit codes.)

### B8. Cross-profile listener conflicts detected only by failure — `Tunnel.isSafeToRun`
`hasConflictingListeners` checks conflicts within one profile only. Two profiles binding
the same local port collide at runtime (masked by B7's retry loop). A preflight "another
profile or app already listens on 8080" check — or at least failing fast on
"Address already in use" — would surface this in seconds.

### B9. No consent moment when quitting with live tunnels — `TunnelStore.quit()`
The update flow carefully asks before stopping tunnels; Quit (footer button or ⌘Q) stops
all of them instantly. macOS convention says apps quit quietly, but for a connection
manager a one-line confirm ("Stop 3 active tunnels and quit?") matches the app's own
interface principle #2 ("Consent licenses the interruption"). Consider it, or at least
an undo-style grace window. *(doc-only)*

### B10. Delete profile has no confirmation and no undo — `TunnelRow` menu
One slip of the cursor on "Delete" (a destructive item in a small popover menu) destroys
the profile permanently. **Fix:** add a `confirmationDialog`. **[implement — PR 1]**

### B11. Minor: hover-only group action menus — `TunnelGroupHeader`
The ellipsis menu sits at `opacity 0.001` until hover. Keyboard users can Tab onto an
invisible control. Prefer always-visible-but-quiet (e.g. `foregroundStyle(.tertiary)`)
or reveal on row focus, not just hover.

### B12. Minor: `List` selection + custom row highlight in Remote Files
`fileList` binds `List(selection:)` *and* draws its own accent background for the selected
row; on some macOS versions this double-paints. Pick one mechanism. **[verify visually]**

---

## 2. General engineering issues

- **G1.** `TunnelStore.save()` and the init decoders use `try?`, discarding encode/decode
  errors silently (B2 is the sharp end of this). At minimum log them.
- **G2.** `RemoteFilesModel` is a 900-line god object: navigation, caching, preview,
  transfer, and server catalog coordination in one type. It works, but future features
  (transfers queue, search) will strain it. Consider splitting Transfer/Preview into
  child models.
- **G3.** Hard-coded UI metrics everywhere (sizes 9.5/10.5/11/11.5/12.5/13.5, radii
  10/12/13, paddings 11/12/14). A tiny design-tokens enum would keep the popover coherent
  as it grows (see V1).
- **G4.** `waitForControlSocket`, `masterArguments` etc. are private; a "show me the exact
  ssh command this profile runs" feature (see D1) wants a pure function, not a copy.
- **G5.** Tests can't be run in this environment; CI runs them on macOS with
  `-warnings-as-errors` — good. Keep it that way.

---

## 3. Performance

- **P1. `~/.ssh/config` is re-read and re-parsed on the main thread after every folder
  navigation.** `RemoteFilesModel.load` → `recordSuccessfulOpen` → `refreshServers` →
  `RemoteServerCatalog.servers(from:)` → `SSHConfigHostReader.load` (up to 1 MB read +
  parse) — per navigation step, plus on every launcher appear and server add/remove.
  Typical configs are cheap, but a 1 MB cap exists precisely because some are big.
  **Fix:** cache the parsed hosts in the `@MainActor` catalog, keyed on file
  mtime+size. **[implement — PR 1]**
- **P2.** Directory-progress polling re-walks the whole partial tree; already mitigated by
  interval scaling (250ms→8s). Fine; note only.
- **P3.** The popover was clearly performance-tuned already (grouping cache, single
  formatter, `LazyVStack`). No further action needed at current scale.
- **P4.** Remote Files `List` rows are cheap. Preview sidebar is lazy. Good.

---

## 4. Missing features (curated, highest value first)

### Tunnel management
- **F1. Search/filter the profile list** — one field; matches name, host, group, ports.
  Becomes essential around ~10 profiles.
- **F2. Duplicate profile** — the classic "same bastion, new port" workflow; rule-level
  duplicate already exists, profile-level doesn't.
- **F3. Drag to reorder** within the ungrouped section (groups are sorted; ungrouped list
  order is insertion order with no user control).
- **F4. Import/export profiles (JSON)** — machine migration and backup; also a natural
  pairing with the Quick Add parser.
- **F5. Auto-start on launch, per profile** — "connect my work tunnels at 9am" without
  touching every row; pairs with Launch-at-Login.
- **F6. Per-profile retry policy** (or a global "pause retries" toggle) — max attempts and
  backoff are hard-coded (10 attempts, up to 60s).
- **F7. Connection uptime + last-error timestamp per row** (or in row detail). Users
  debugging flaky Wi-Fi will love "up 3h 12m, restarted 4×".
- **F8. Notifications on permanent failure / auto-reconnect** (opt-in, off by default) —
  the retry loop is invisible when the popover is closed.
- **F9. Global hotkey** to open the popover (Carbon `RegisterEventHotKey`; no
  accessibility permission needed). E.g. ⌃⌥R.
- **F10. `relaybar://` (and `ssh://`) URL scheme** for one-click profile import from
  wikis/readmes.
- **F11. Per-rule enable/disable toggle** — suspend a rule without deleting it.

### Editor
- **F12. Validation messages** — Save is silently disabled; the user gets no reason. Show
  the first blocking issue ("Rule 2's port must be 1–65535", "Rules 1 and 3 listen on the
  same port", "Choose a Remote SOCKS destination policy").
- **F13. Jump-host and identity affordances** — `-J`/`-i` only arrive via import; a
  "Jump host" field with validation would be friendlier than "additional arguments".
- **F14. Batch import** of several `ssh` commands at once (one profile per line).

### Remote Files
- **F15. Clickable breadcrumb path bar** — the centered monospaced path is already
  begging to be segmented; click a segment to jump.
- **F16. Client-side folder filter** (type-ahead, like Finder) — instant on cached
  listings.
- **F17. Sort control + hidden-files toggle** (dotfiles are always shown; some folders
  are 80% dotfiles).
- **F18. Multi-select downloads + a transfer queue** (one transfer at a time today;
  second click on Download is ignored).
- **F19. Favorites/recents per server** — remember the last N paths per host; "reopen
  /srv/app/output" is the single most repeated action.
- **F20. Richer preview types** — PDF, plain text, JSON, CSV (the QuickLook-style preview
  infrastructure already exists for images/markdown).
- **F21. Upload** (opt-in, off by default, drag-drop onto the window) — would turn
  Remote Files from a viewer into a real tool; needs a careful security story.
- **F22. Reveal-downloads preference** ("always reveal in Finder when done").
- **F23. Symlink navigation** (B4).
- **F24. Window title shows current path** for Mission Control/⌘Tab context.

### System integration
- **F25. VoiceOver announcements** on tunnel state transitions (the accessibility
  groundwork is already there).
- **F26. Menu-bar count badge / per-state icon variants** (see D2).
- **F27. Shortcuts/AppleScript surface** for "start profile X" (heavy; long-term).

---

## 5. Visual & layout issues

- **V1. Inconsistent design tokens.** Corner radii mix 13 (cards), 12 (quick add), 10
  (rules, SOCKS panel), 7 (markdown blocks); section labels are 9.5pt semibold tracked
  caps in the editor but 10.5pt medium sentence-case for group headers; paddings mix
  11/12/14. None of it is *wrong*, but the slight variance reads as "assembled" rather
  than "designed". Pick a scale (e.g. radius 10/14, label 10pt/0.5 tracking) and apply.
- **V2. Four-segment `Picker`** ("Local / Local SOCKS / Remote / Remote SOCKS") inside a
  380pt popover truncates or squeezes; short labels ("Local", "SOCKS", "Remote",
  "Remote SOCKS") or a menu picker would breathe. **[verify visually]**
- **V3. Fixed-point typography everywhere.** Fine on macOS, but it forfeits Dynamic-Type
  accessibility scaling; a future pass could map to text styles.
- **V4. Flat popover background** (`windowBackgroundColor`) — a `.regularMaterial`-backed
  popover (Control-Center-like) would look more "system high-value". Needs visual
  verification for text contrast in both appearances.
- **V5. Status indicator is an 8pt dot.** A tiny pulse (animating opacity only while
  `.starting`/`.retrying`) would communicate liveness at zero cost. Subtle, not novelty.
- **V6. Empty state** is good copy-wise; add a "Paste an SSH command" affordance that
  pre-fills the editor from the clipboard when it looks like an ssh command (see D3).
- **V7. Remote Files toolbar** — the path is monospaced but not copyable; a small copy
  button or click-to-copy would remove a frequent trip to the row menu.
- **V8. Group header hover reveal** (B11) — also a visual discoverability issue.

---

## 6. User experience / convenience / speed

- **U1.** Status-item tooltip/accessibility value doesn't reflect state — hovering the
  menubar icon says nothing. A live tooltip ("3 tunnels active · RelayBar") is a 3-line
  change. **[implement — PR 1]**
- **U2.** No keyboard flow in the list: ⌘N for new profile, ↑/↓ to move, Space/Enter to
  toggle, ⌘F to search, ⌘1…9 to toggle the first nine. The popover is already the app's
  whole surface; make it keyboard-fast.
- **U3.** "Open in browser" on a stopped tunnel starts it and opens when ready (good!)
  — but there's no equivalent "copy URL" on the row. Add "Copy URL" next to the rule
  copy actions for one-rule profiles.
- **U4.** Editing keeps its navigation state between popover openings (nice touch) — but
  the editor's focus is lost on reopen; restore focus to the primary field per screen.
- **U5.** Quick Add only on the New Profile screen. Let Edit also re-import (replace
  rules) — power users keep their commands in notes.
- **U6.** The tunnel row's ellipsis menu contains the only Copy endpoints / Reveal
  socket actions — consider a hover-visible "copy" chip for the one-rule case (most
  common shape).
- **U7.** Remote Files launcher remembers the last path per host? It doesn't (F19).

---

## 7. Aesthetics — "high-value macOS app"

- **A1.** The app mark (gradient rounded square + arrows) is decent; consider a matching
  monochrome/duotone treatment in Settings' About footer (today: plain text version row).
- **A2.** Consistent card treatment: tunnel rows use `controlBackgroundColor` cards;
  the editor uses `Color.primary.opacity(0.035)` panels — unify on one surface treatment.
- **A3.** Buttons: the circular play/stop toggle is the app's best control; reuse that
  visual language (circle chips) for the row's safari/ellipsis actions so the row reads
  as one family.
- **A4.** Transitions between list → editor → settings are hard cuts; a gentle push
  slide (0.15s) would make the popover feel like one continuous surface.
- **A5.** Update the empty-state artwork to the same arrows motif as the menubar glyph
  (today it's a triangle network symbol — fine, but the brand mark is the two arrows).
- **A6.** Menubar icon: `arrow.left.arrow.right.circle[.fill]` is a good, quiet choice;
  resist the urge to make it louder, but a per-state "dashed" variant while any profile
  is connecting (opt-in) is tasteful and useful.

---

## 8. Novel / delightful / quirky ideas

- **D1. "The exact command" panel.** In the editor, a collapsible footer showing the
  literal `ssh -N -T -M -S … -L 8080:localhost:3000 user@host` line the app will run,
  generated by the same code that runs it. Transparency is trust — and it teaches users
  what the menubar app actually does. (Needs a pure `masterArguments` extraction — G4.)
- **D2. Living menubar icon.** Filled circle while any tunnel runs (today) + a subtle
  one-time "ping" animation when a tunnel comes up; opt-in count badge ("3") next to the
  glyph for multi-tunnel users.
- **D3. Clipboard-aware empty state.** "We noticed an SSH command on your clipboard —
  import it?" — one button, uses the existing parser, only when the clipboard plausibly
  starts with `ssh `.
- **D4. Per-tunnel connection log.** The store already buffers the master's stderr
  (16 KB, bounded!). A "View Log" sheet per row surfaces auth problems
  ("Offered public key… rejected") that today compress into one red line. Nearly free,
  hugely useful, and uniquely honest for a GUI-over-ssh app.
- **D5. Sound on connect** (opt-in, off): a soft "Pop" via `NSSound` when a profile
  reaches `.running` after a failure/retry — tunnels are slow to come up; a quiet audio
  cue means you can stop staring.
- **D6. Keyboard-first "quick switcher"** (⌘K): fuzzy-search profiles *and* recent remote
  paths from anywhere in the app.
- **D7. "Panic stop"** — one menu-bar-extra click with ⌥ held stops every tunnel
  (airport-security moment). Quirky, memorable, occasionally exactly right.
- **D8. Health heartbeat.** Tiny per-row latency graph of the forwarded port
  (one TCP connect per N seconds, opt-in). Turn the row into a living status board.
- **D9. Group cheer.** When "Start All" finishes, a one-line summary toast inside the
  popover ("Work: 3 up, 1 failed — click for details") instead of scanning rows.

---

## 9. Implementation plan for this session

High-confidence, small-blast-radius set (this environment cannot compile Swift; CI + GLM
5.3 review are the verification loop):

**PR 1 — `glm/review-hardening`** (branch off `main`):
1. B10 delete-profile confirmation dialog.
2. U1 status-item tooltip + accessibility value reflecting active tunnel count.
3. P1 catalog-side `~/.ssh/config` caching (mtime+size keyed).
4. B2 quarantine corrupt saved-profiles blob before it can be overwritten.
5. B5 control-socket readiness window 12s → 30s, failure copy corrected.
6. CHANGELOG + system-spec updates for each.

**PR 2 — `glm/auto-restart-on-edit`** (branch off `main`):
1. B1 restart a running profile with its new configuration after Save.
2. Update affected integration tests to assert restart behavior.
3. CHANGELOG + spec updates.

**Deferred to ANALYSIS.md** (valuable, but too large or too risky without a local
compiler): B3 live countdown, B4/B23 symlink navigation, B6 live server list, B7/B8
fail-fast classification, F1–F27 minus implemented items, V1–V8, D1–D9. These become the
shovel-ready backlog for future sessions.

---

*End of review.*
