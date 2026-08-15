# RelayBar — analysis and delivery backlog

Updated: 2026-08-14

This is the durable backlog produced by consolidating the repository's earlier
`glm.md` review with the point-in-time [`sol.md` audit in PR #11](https://github.com/L-K-M/RelayBar/pull/11).
The latter audited revision `1faa8d9`; this consolidation was reconciled against
`origin/main` at `e6196c9` and open pull requests through #29 at 23:29 UTC on
2026-08-14. Source remains authoritative when the repository changes after that
snapshot.

`RB-###` identifiers below are stable analysis IDs, not task-spec numbers. Create a
new numbered file under `docs/task-specs/` only when an entry is selected for
delivery. The live registry currently has duplicate claims at 047 (PRs #17/#28) and
048 (PRs #16/#29); both newer PRs have been notified. Number 055 was the first
unclaimed value at this snapshot, but do not allocate it—or trust any number here—
without rechecking `main` and every open PR filename immediately before use.

The intended product boundary is a fast native forwarding tool that respects the
user's existing OpenSSH setup, not a general remote-terminal client. Competitors are
useful market signals: Core Tunnel advertises reconnect policy, option editing,
tags, import/export, sync, and Shortcuts on its [product page](https://codinn.com/tunnel/)
and [App Store listing](https://apps.apple.com/us/app/core-tunnel/id1354318707?mt=12),
while Royal TSX documents tunneling, automation, custom organization, session
overview, and file transfer on its [macOS feature page](https://www.royalapps.com/ts/mac/features).
The goal is to learn from those expectations without widening RelayBar's trust
boundary by default.

## Before picking up work

- Fetch remotes and inspect open PRs. Open work is not landed behavior, but it must
  not be unknowingly duplicated.
- Keep each independently reviewable outcome on its own `codex/` feature branch and
  follow the task-spec completion rules in `AGENTS.md`.
- Pick up only entries marked **Ready** in the priority map. **Design first**,
  **Re-scope**, **Split first**, **Prototype**, and **Blocked** entries must become a
  smaller accepted task before implementation.
- Update the affected system spec in the same change. A task spec describes proposed
  work; source and system specs describe implemented behavior.
- Run the full warnings-as-errors tests and unsigned Release build on macOS, plus
  `git diff --check`. Record required visual, accessibility, live-SSH, security, and
  performance evidence before archiving a task.
- Do not claim a stutter or improvement from source inspection alone. Add signposts,
  reproduce on a Mac, and retain only changes with material evidence.
- Treat hostnames, identity paths, remote paths, diagnostics, and exported profiles
  as potentially sensitive. Redact or obtain explicit consent before persisting,
  exporting, notifying, or copying them.

## Reconciled delivery status

Completed work is intentionally omitted from this backlog. Use the archived task
specifications and Git history for that record; do not re-add an accepted outcome
unless current source proves a distinct regression.

### Audit implementations still in pull requests

These are implemented and reviewed or actively finishing their final review cycle.
Do not pick them up as new backlog work; verify their live status and overlap before
merging.

| Analysis | Task | Pull request | Delivered outcome |
| --- | --- | --- | --- |
| audit | — | [#11](https://github.com/L-K-M/RelayBar/pull/11) | Point-in-time `sol.md` review ledger |
| RB-001 | 047 | [#17](https://github.com/L-K-M/RelayBar/pull/17) | Safe SSH master configuration and process invariants |
| RB-002 | 037 | [#14](https://github.com/L-K-M/RelayBar/pull/14) | Atomic, correctly budgeted shared control paths |
| RB-003 | 048 | [#16](https://github.com/L-K-M/RelayBar/pull/16) | Invalid/unreadable SFTP output is an error, not an empty directory |
| RB-004 | 049 | [#18](https://github.com/L-K-M/RelayBar/pull/18) | Destructive profile-deletion confirmation |
| RB-005 | 050 | [#20](https://github.com/L-K-M/RelayBar/pull/20) | Truthful retry/browser copy, full-value help, and row action labels |
| RB-006 | 051 | [#21](https://github.com/L-K-M/RelayBar/pull/21) | Cancellation for the initial Remote Files open |
| RB-007 | 052 | [#23](https://github.com/L-K-M/RelayBar/pull/23) | Closed-popover failure attention and status-item accessibility summary |
| RB-008 | 053 | [#24](https://github.com/L-K-M/RelayBar/pull/24) | Stable labels for principal tunnel and Remote Files forms |
| RB-009 | 054 | [#15](https://github.com/L-K-M/RelayBar/pull/15) | Truthful updater, privacy, security, and task-index documentation |

Task 047 also appears in PR #28 and Task 048 also appears in PR #29. The code PRs are
independent, but those documentation identifiers must be made unique before either
pair can merge.

Two overlaps need an explicit merge choice: PR #20's truthful static retry copy and
[PR #12](https://github.com/L-K-M/RelayBar/pull/12)'s real live countdown both replace
the same misleading row text; PR #18 and the deletion portion of
[PR #4](https://github.com/L-K-M/RelayBar/pull/4) address the same destructive path.
Do not try to combine both implementations mechanically.

### Other open work to account for

- [PR #4](https://github.com/L-K-M/RelayBar/pull/4): bundled delete confirmation,
  status summary, SSH-config cache, corrupt-payload backup, and readiness-window
  hardening. Its broad scope partially overlaps RB-012, RB-018, RB-004, and RB-007.
- [PR #5](https://github.com/L-K-M/RelayBar/pull/5): click-open-status-item popover
  dismissal.
- [PR #6](https://github.com/L-K-M/RelayBar/pull/6): restart an active profile after
  a connection-changing edit.
- [PR #8](https://github.com/L-K-M/RelayBar/pull/8): Back from a direct remote file
  opens its containing folder.
- [PR #12](https://github.com/L-K-M/RelayBar/pull/12): live retry countdown.
- [PR #13](https://github.com/L-K-M/RelayBar/pull/13): confirm explicit Quit while
  tunnels are active.
- [PR #22](https://github.com/L-K-M/RelayBar/pull/22): bounded `Include` traversal
  while discovering SSH-config hosts.
- [PR #25](https://github.com/L-K-M/RelayBar/pull/25): secure final permissions for
  downloaded payloads.
- [PR #26](https://github.com/L-K-M/RelayBar/pull/26): remember the last remote path
  per connection.
- [PR #27](https://github.com/L-K-M/RelayBar/pull/27): clipboard-aware Quick Add.
- [PR #28](https://github.com/L-K-M/RelayBar/pull/28): show the editor's first
  blocking validation reason. This partially delivers RB-020 and currently collides
  with PR #17 on Task 047.
- [PR #29](https://github.com/L-K-M/RelayBar/pull/29): shared hover-responsive icon
  buttons, row-menu treatment, and full error help. It overlaps PR #20 and part of
  RB-028, and currently collides with PR #16 on Task 048.

## Priority map

| ID | Priority | Outcome | Readiness / dependency |
| --- | --- | --- | --- |
| RB-010 | P0 | Await and safely reap every normal shutdown | **Design first**; integrates updates |
| RB-011 | P0 | Reconcile crash/force-quit orphans | **Design first**; threat model/live SSH |
| RB-012 | P0 | Corruption-safe recoverable persistence | **Design first**; storage/migration |
| RB-013 | P0 | Make timeout truly bounded | **Ready after RB-010** |
| RB-014 | P0 | Stop retry flapping and skip permanent runtime failures | **Ready**; choose stability window |
| RB-015 | P1 | Preserve final SSH diagnostics on fast exit | **Ready after RB-010** |
| RB-016 | P1 | Bound importer, model, and payload complexity | **Design first**; choose limits |
| RB-017 | P1 | Fix the measured large-Markdown bottleneck | **Measure first** on macOS |
| RB-018 | P1 | Move/cache SSH-config discovery off the main actor | **Re-scope** after PRs #4/#22 |
| RB-019 | P1 | Make lifecycle-changing decisions explicit | **Re-scope** after PRs #6/#13/RB-010 |
| RB-020 | P1 | Complete actionable editor validation | **Re-scope** after PR #28 |
| RB-021 | P1 | Inspect and safely edit imported SSH options | **Ready**; strict option policy |
| RB-022 | P1 | Add bounded inspector, history, diagnostics, and recovery | **Design first**; privacy/redaction |
| RB-023 | P1 | Make 50–100 profile sets fast to operate | **Split first** into listed children |
| RB-024 | P1 | Add opt-in autostart and network-aware recovery | **Design first**; desired-active policy |
| RB-025 | P1 | Make Remote Files a focused native browser | **Split/re-scope** after open PRs |
| RB-026 | P1 | Finish accessibility and localization foundations | **Split first**; packaged Mac evidence |
| RB-027 | P1 | Choose one coherent fork/update identity | **Blocked** on owner decision |
| RB-028 | P2 | Rebuild visual QA, tokens, and icon family | **Prototype first**; account for PR #29 |
| RB-029 | P2 | Add first-run guidance and error recovery | **Ready**; never weaken SSH security |
| RB-030 | P1 | Keep restart behind retiring listener ownership | **Ready after RB-010** |
| RB-031 | P2 | Remove duplicated unnamed-row information | **Prototype first** with snapshots |
| RB-032 | P1 | Fail fast on cross-profile listener conflicts | **Ready** |
| RB-033 | P1 | Keep the Remote Files server catalog live | **Ready** |
| RB-034 | P1 | Follow remote directory symlinks truthfully | **Ready** |
| RB-035 | P2 | Add bounded per-connection recent path history | **Ready after PR #26** |

## P0 lifecycle and data-integrity work

### RB-010 — Coordinate, await, and safely reap every normal shutdown

`applicationShouldTerminate` normally returns `.terminateNow`.
`applicationWillTerminate` closes Remote Files and calls `stopAll`, but the process
cannot await delayed escalation and cleanup. Cooperative children usually exit;
stubborn or slow SSH children can survive with listeners intact. Forwarding and
Remote Files masters also retain delayed numeric-PID signal paths with a PID-reuse
check-to-signal gap.

Introduce one serialized child owner for forwarding masters, control helpers, the
Remote Files master, and SFTP children. Every normal termination route should stop
accepting work, return `.terminateLater`, send `SIGTERM`, await ownership-confirmed
exit, escalate once without a recycled-PID gap, clean artifacts, then reply to
AppKit. Integrate Sparkle's deferred relaunch gate and termination reentrancy. Keep
command builders pure and testable rather than rebuilding argument arrays inside the
coordinator.

Acceptance: footer Quit, Cmd-Q, logout/shutdown, Remote Files transfer, update
relaunch, cooperative children, stubborn children, and concurrent helpers leave zero
owned children and zero private control directories. No signal is sent after a child
is reaped.

### RB-011 — Reconcile orphaned tunnels after crash or force-quit

A crash or `SIGKILL` cannot run termination cleanup. Foreground masters use
`/dev/null`, and `ControlPersist=no` does not tie their lifetime to RelayBar, so an
invisible forward can survive and later appear only as a port conflict.

Persist a private minimal ownership manifest containing a launch nonce, private
control location, and safely verifiable process identity. At startup, inspect only
permission-checked app-owned artifacts; retire a positively identified orphan through
its control socket or present an explicit recovery choice. Never kill from an
unverified stale PID. Garbage-collect dead directories idempotently.

Acceptance: force-kill with a live real forward, relaunch, and prove the listener is
safely retired or explicitly recovered. Crafted directories, symlinks, other-user
artifacts, and recycled PIDs remain untouched.

### RB-012 — Make saved configuration corruption-safe and recoverable

Tunnel, saved-server, and recent-server arrays are decoded all-or-nothing. A corrupt
record can collapse a whole collection to empty, and a later save can overwrite
recoverable bytes. Silent `try?` encode/decode paths also leave no useful Console
diagnostic. PR #4's quarantine, if merged, protects raw bytes but does not complete
record-level salvage or recovery UX.

Move to an atomic versioned Application Support document or an equivalent backup
scheme. Preserve undecodable bytes, block ordinary empty-state writes after a load
failure, retain timestamped last-known-good backups, salvage individually valid
records where safe, report rejected records, and provide restore plus versioned
export/import. Log bounded non-sensitive failure context. Export UX must disclose
that hostnames and identity paths may be sensitive.

Acceptance: truncated JSON, unknown enums, one invalid sibling, duplicate IDs,
write/rename failure, and failed migration never silently erase good records or
overwrite the last good payload. Restore and export/import round-trip every supported
field, including imported options and rules.

### RB-013 — Make timeout actually mean bounded

Control and startup timeout paths call `process.terminate()` and then depend on a
termination handler. A child that ignores `SIGTERM` can remain alive forever, leaving
continuations unresolved and a profile stuck Starting. The current timeout fixture
cooperates with TERM.

Route timeout, cancellation, rollback, stop, and quit through RB-010's child owner
with exactly-once completion. Add stubborn master and stubborn control-helper
fixtures. A timeout must lead to bounded kill/reap, rollback, then retry/failure—not
merely append a timeout string to a still-running process.

Acceptance: every timeout path completes within its documented bound plus a small
test tolerance, owns no child/artifact afterward, resumes its continuation once, and
cannot let a late callback mutate a newer generation.

### RB-014 — Prevent endless retry flapping and pointless retries

After successful rule installation, `retryAttempts[id]` resets immediately. A master
that reaches Running and exits seconds later therefore retries forever as attempt 1,
defeating the documented ceiling and wasting energy. Separately, deterministic
child-process failures such as rejected credentials or host-key verification should
not burn the same transient-network retry loop. Current `main` already rejects an
unsafe profile and an app-owned local-socket preflight failure before desired/retry
state; keep cross-profile listener ownership in RB-032 rather than reclassifying it
here.

Reset the retry budget only after a documented stability window, or count consecutive
short-lived runs. Key stability timers by launch generation, define sleep/wake
behavior, and cancel them on user stop. Add a typed, conservative permanent-failure
classifier; unknown/network-temporary failures remain retryable. A later preference
may expose pause-retries or per-profile policy, but do not mix that product choice
into the correctness fix.

Acceptance: a deterministic flapping fixture reaches Failed at the configured cap, a
stable fixture earns one reset, permanent fixtures make zero automatic relaunches,
and transient fixtures retain bounded backoff. Row copy and attempt counts remain
truthful through sleep, manual Retry, and Stop.

## P1 reliability, performance, and product work

### RB-015 — Preserve final SSH diagnostics on fast exit

Master stderr and termination enqueue independently. Exit classification can read a
partial buffer and clear the handler before a final owned drain; late appends can
arrive after cleanup. If the bounded buffer begins inside a UTF-8 scalar, strict
decoding can discard the whole message.

Give stderr one serialized owner, detach then drain on exit, key appends to the exact
process/generation, and truncate on valid scalar boundaries or decode loss-tolerantly.

Acceptance: repeated immediate-exit fixtures always retain their final actionable
line, including a multibyte truncation boundary, without accepting output from an old
generation or exceeding the byte cap.

### RB-016 — Bound importer, profile, and persistence complexity

Command bytes, tokens, option values, rules per profile, total profiles, visible
strings, and total persisted payload are not consistently bounded. A huge paste or
tampered payload can drive excessive parsing, validation, persistence, and thousands
of SwiftUI rows.

Choose realistic exact limits, document them in the system contract, reject before
mutating editor state, and validate decoded storage again before publication. Keep
batch Quick Add as a separate feature after the single-command boundary is safe.

Acceptance: exact-boundary and one-over fixtures for every dimension fail fast and
transactionally with a specific recoverable message. No partial import, save, or UI
publication occurs.

### RB-017 — Optimize the measured Markdown bottleneck

Repository evidence records roughly one second in Release for
`ObsidianMarkdownCompatibility.renderSource` on a 776 KB fixture, while the supported
limit is 2 MiB. The pipeline makes repeated whole-document scans and per-line
`[Character]` allocations. A cache-miss syntax highlight can also run JavaScriptCore
synchronously from `MarkdownCodeBlock.body` on the main thread.

Add signposts for transforms, parse, highlight, and first render. Benchmark 100 KB,
776 KB, and maximum-size representative documents. Consolidate lexical passes or
skip absent enrichments, and precompute highlighting off-main with cancellation and
an aggregate budget. Preserve the security/compatibility fixture corpus byte-for-byte.

Acceptance: demonstrate a material improvement (3× is a useful target) and a measured
main-thread frame budget on a Mac. Do not land an unmeasured micro-optimization.

### RB-018 — Move and cache SSH-config discovery off the main actor

`RemoteServerCatalog` is `@MainActor`; catalog construction synchronously reads and
parses up to 1 MiB of SSH config during model creation and refresh. PR #4 may add
mtime/size caching, and PR #22 may add bounded `Include` traversal; re-scope after
those settle rather than replacing them.

If those PRs land, the remaining outcome is bounded I/O and parsing away from the
main actor plus deterministic cache invalidation based on file identity and
content-relevant metadata. Do not duplicate `Include` traversal in a follow-up unless
review finds a concrete gap in PR #22.

Acceptance: an injected slow maximum-size configuration does not stall launcher
interaction; unchanged files are not reread; atomic replacement, modification,
deletion, and permission failure invalidate deterministically. Preserve PR #22's
cycle/glob/aggregate fixtures if that work is present.

### RB-019 — Make lifecycle-changing decisions explicit and recoverable

Quit, connection-changing edits, and abandoning a long draft can stop or discard more
than their labels imply. PR #6 and PR #13 implement parts of this outcome; inspect
their final behavior before creating follow-up work.

After RB-010 supplies real shutdown semantics, use one termination decision for
footer Quit, Cmd-Q, and normal system termination: **Stop N and Quit** or Cancel.
Connection-changing edits should offer **Save & Restart**, **Save & Stop**, and
Cancel; metadata-only edits remain live. If PR #6 intentionally chooses a narrower
automatic-restart contract, record that product decision instead of silently losing
the stop/cancel alternatives. Pristine drafts leave immediately; dirty drafts offer
Discard/Keep Editing, and transient popover closure preserves the draft for the
session.

Acceptance: every entrance route has the same lifecycle result, no prompt repeats
during reentrant termination, active listeners are not silently abandoned, and a
dirty draft survives accidental popover closure without being persisted.

### RB-020 — Replace disabled-save guessing with actionable validation

`builtTunnel` can reject hosts, ports, Unix paths, masks, listener conflicts, reverse
policies, and unsafe options, but the visible result on `main` is usually only a
disabled Save button. PR #28 adds one first-blocking-reason line; if it lands, retain
that foundation and scope the remaining task to field/rule placement, error summary,
and focus behavior.

Introduce typed validation results, inline messages beside the responsible field or
rule, a screen-reader error summary, and first-invalid focus/scroll. Duplicate
listeners should name both rule numbers. Keep validation pure so import, editor, and
persistence boundaries share it.

Acceptance: each invalid field fixture receives a stable purpose-specific message;
Save is never the sole explanation; submitting focuses the first error; correcting
it preserves unrelated draft values; VoiceOver announces the summary once.

### RB-021 — Make imported SSH options inspectable and editable

Edit currently summarizes preserved imported options without showing the values that
materially define the connection: port, jump host, identity path, address family, and
allowed `-o` values. The now-landed Copy SSH Command action improves export but does
not make editor state transparent.

Add safe structured fields with contextual help, removal/editing, a redacted
command preview, and a transactional re-import route on Edit. The preview and copied
form must derive from the same production argument builder that execution uses;
display redaction is a final presentation layer, not a second command generator. Do
not become an arbitrary `ssh_config` editor or admit command-executing options.

Acceptance: supported options round-trip through import, edit, copy, persistence,
and re-import; removal is explicit; invalid re-import leaves the draft untouched;
preview fixtures cannot drift from execution arguments; redaction never emits secret
material or private-key contents.

### RB-022 — Add a bounded inspector, event history, and recovery actions

Rows expose only one current line and Remote Files error strips are capped, so the
sequence leading to failure disappears. Add a profile inspector with phase, uptime,
assigned automatic ports, all rules, bounded full error, retry timeline, safe
effective metadata, Retry/Edit, and Copy Diagnostics. Keep a session-bounded history
for start, connected, retry, recovery, stop, failure, update interruption, and Remote
Files session events.

Optional failure/recovery notifications should be off by default, deduplicated, and
added only after the in-app history is useful. A group Start All summary belongs here
rather than as an ephemeral unexplained toast.

Acceptance: history has explicit count/byte/age bounds, survives row-state
replacement for the current session, remains ordered under concurrent events, and
redacts secrets plus remote-file content. Copy Diagnostics is deterministic and
reviewable in tests.

### RB-023 — Make large profile sets fast to operate

This is an epic; assign a child analysis/task ID to one outcome at a time. The fixed
380×440 popover shows few large cards and lacks quick filtering, keyboard
selection, global lifecycle actions, reorder, favorites, compact density, and
adaptive height. Duplicate Profile is already on `main`; do not reimplement it.

Deliver the remainder as separate tasks:

1. Command-F or Command-K filtering by name, group, host, and endpoint.
2. Keyboard selection with arrows, Space toggle, Return edit/open, and named row or
   group menus.
3. Start All/Stop All with an exact target summary and confirmation where destructive.
4. Persistent reorder, favorites/pinning, collapsible groups, and optional compact
   rows.
5. Adaptive popover height within the active screen's safe area and per-screen focus
   restoration.

Acceptance for every subtask: a 50–100-profile fixture remains responsive; filtering,
ordering, and view density never alter lifecycle identity or process ownership;
keyboard and VoiceOver paths match pointer actions. Group ellipsis actions must be
discoverable by focus, not hover alone.

### RB-024 — Add opt-in autostart and network-aware recovery

Launch at Login deliberately starts no profiles. There is no per-profile desired
start policy or wake/network observer; keepalives may take roughly 90 seconds to
notice a dead path.

Add **Start when RelayBar opens**, default off, then define update relaunch, wake,
VPN, captive portal, and rapid path-churn behavior. Debounce path events and restart
only profiles whose visible desired-active policy licenses it.

Acceptance: first install starts nothing; consent is per profile, visible, and
reversible; wake/network storms produce at most one current-generation restart;
manual Stop suppresses recovery; update relaunch preserves the documented intent.

### RB-025 — Make Remote Files feel like a native focused browser

This is an epic, not one implementation task. Re-scope after PR #8 (Back to
containing folder) and PR #26 (last path) settle; take RB-033 and RB-034 as separate
correctness tasks. Then assign child IDs to the remaining outcomes before delivery:

- a real path control with Up/Command-Up, Command-L, Copy Path, clickable ancestors,
  and explicitly consented server/path favorites;
- native Name/Date/Size/Kind sorting, hidden-file control, and Command-F filtering
  over only the loaded snapshot;
- first-row/list focus so arrows, Space, Return, and Command-Down work immediately;
- stable window position/anchor while resizing and a title that includes useful
  current-path context;
- an inactivity watchdog for listings and progress-reset timeout for transfers;
- a bounded preview LRU, one-neighbor prefetch, image Fit/Actual Size/zoom, and
  separately bounded plain-text/JSON/YAML/CSV/log/PDF previews;
- one native selection treatment—remove the double accent paint from combining
  `List(selection:)` with a custom selected-row background after visual verification.

Before queued multi-downloads or richer previews make `RemoteFilesModel` larger,
split transfer and preview ownership into focused child models where measurement
shows it reduces invalidation or complexity.

Shared epic acceptance: path and selection remain truthful; a 10,000-row fixture
keeps keyboard navigation responsive; sort/filter do not trigger network I/O; caches
and watchdogs have exact bounds; session-only path privacy remains the default. Each
child needs narrower acceptance before implementation.

### RB-026 — Finish the macOS accessibility and localization foundation

This is an evidence program, not one code task; split typography, state semantics,
motion/contrast, keyboard routing, and localization into independently accepted
children. Core surfaces contain more than 100 fixed-point fonts, including 9.5–10.5
pt tertiary copy. Some state remains dependent on a tiny color dot; async errors and
transfer completion are not consistently announced; explicit animations need Reduce
Motion verification; menu shortcuts are incomplete; and there is no String Catalog
despite long-localization claims.

Migrate deliberately to semantic or relative text styles, strengthen contrast, add
non-color state labels/traits and deduplicated async announcements, honor Reduce
Motion/Increase Contrast/Reduce Transparency, complete standard shortcuts
(`Command-N`, `Command-,`, Escape, default Save), and introduce plural-aware
localization with pseudolocalized and RTL fixtures.

Acceptance: packaged-app evidence covers VoiceOver, Accessibility Inspector,
keyboard-only use, maximum text size, high contrast, reduced motion/transparency,
light/dark, long localization, and RTL. No tiny caption is the only carrier of state.

### RB-030 — Keep restart behind retiring listener ownership

`stop` removes the old launch from runtime ownership before a stubborn master is
necessarily reaped. Immediate Restart can install the same TCP or Unix listeners
while the old owner still holds them, causing avoidable address-in-use failure.

Retain a per-profile retiring-launch barrier. A replacement may authenticate in
parallel only if it cannot install listeners until the prior owner is proven reaped.
Build this on RB-010 rather than adding another delayed PID signal.

Acceptance: a listener-holding stubborn fixture restarts without transient
address-in-use failure, duplicate masters, or stale cleanup touching the replacement.

### RB-032 — Fail fast on cross-profile listener conflicts

`Tunnel.isSafeToRun` catches overlaps inside one profile, not between profiles. Two
desired-active profiles can bind the same Local TCP or Unix listener, then consume
the retry loop before surfacing a runtime error.

Add a namespace-aware preflight against other desired-active and retiring profiles.
Report both profile names and the exact listener. For non-RelayBar occupants, a
non-destructive bind probe or platform diagnostic may identify the local owner where
permission allows. Offer an explicit editor recovery that changes an eligible Local
TCP listener to Automatic port `0`; RelayBar must never kill the owner or silently
change a fixed port.

Acceptance: IPv4/IPv6 wildcard versus loopback overlap, exact host overlap, Unix path
overlap, automatic ports, stopped profiles, concurrent starts, and retiring owners
have deterministic tests. A known conflict launches no master and schedules no retry.
Owner lookup failure remains harmless, and choosing the automatic-port recovery is a
user-confirmed profile edit with normal validation and restart semantics.

### RB-033 — Keep the Remote Files server catalog live

`RemoteFilesWindowController.show` pushes tunnel definitions when the window is
opened or explicitly shown again. Adding, editing, or deleting a profile while the
window stays visible can leave the Server picker stale even though
`RemoteFilesModel.updateTunnels(_:)` already handles selection preservation.

Observe the store's tunnel publication for the window lifetime and forward bounded,
main-actor updates to the model. Stop observation on controller teardown. Preserve a
selected saved host; if a selected forwarding profile disappears, choose the
documented fallback without interrupting an already-owned browse session.

Acceptance: add/edit/delete while launcher and browser are visible refresh exactly
once, preserve valid selection, choose a deterministic fallback, and create no
observer cycle or duplicate SSH session.

### RB-034 — Follow remote directory symlinks truthfully

`SFTPListingParser.directFileEntry` and `RemoteFilesModel.commitLoadedFile` can turn a
symlinked directory into a single dead-end `symbolicLink` row. The parser discards the
`name -> target` relationship, and activation downloads the link instead of
navigating. Symlink rows inside ordinary listings have the same ambiguity. PR #8's
Back-to-parent behavior does not resolve traversal.

Retain the parsed link target as bounded typed metadata. On explicit activation,
distinguish a link that resolves to a directory, list the resolved location, and keep
the path bar truthful about the resulting path. Define relative targets, chained
links, loops, broken links, and targets outside the starting folder; do not infer a
directory solely from its display name or silently follow on preview.

Acceptance: direct-path and normal-list fixtures cover relative/absolute directory
links, file links, broken links, chains, and loops. Directory activation navigates
once to a truthful resolved path; file activation retains bounded download behavior;
malformed `->` text cannot inject an SFTP command or create an infinite traversal.

### RB-035 — Add bounded per-connection recent path history

PR #26 remembers one last path per connection. That improves reopen behavior but does
not replace the earlier need for a small history when users alternate between paths
such as `/srv/app`, `/var/log`, and an output folder.

After PR #26 settles, extend its connection identity and privacy model to the last N
successful paths, deduplicated by normalized path and bounded globally as well as per
connection. Keep it distinct from explicitly pinned favorites. Provide Clear History
and avoid recording failed, cancelled, or merely typed paths.

Acceptance: exact eviction order, deduplication, identity changes, cancellation,
failed opens, storage corruption, and Clear History are deterministic. The UI never
mixes implicit history with explicit favorites, and path persistence remains visibly
controllable.

## P2 product trust, activation, and visual quality

### RB-027 — Choose one coherent fork/update identity

This repository identifies itself as an L-K-M fork while the bundle ID, Sparkle feed
and public key, website, repository links, and release documentation remain upstream.
A future upstream update can replace the fork-specific behavior.

Choose one model: upstream-tracking patch build, independently maintained fork, or
changes intended to merge upstream. An independent product needs fork-owned bundle
and update identity, feed, signing key, links, provenance, and migration. An
upstream-updatable patch must disclose that updates can replace fork modifications
and should not enable them until equivalent fixes are upstream. About/diagnostics
should identify channel, owner, version/build, and commit.

Acceptance depends on the owner's decision; do not ship a partial identity mix.

### RB-028 — Rebuild visual QA, design tokens, and the icon family

This is a design/QA epic. Prototype and approve the direction, then assign separate
child tasks for tokens/surfaces, interaction states, icon assets, snapshot tooling,
and marketing recapture. Committed screenshots omit current controls or show
already-fixed defects, while the snapshot harness mostly proves an image was written
rather than comparing a reviewed
golden. Core surfaces mix radii (7/10/12/13), label systems, padding, and card fills.
The high-glow 1024 icon and small opposed-arrow mark do not yet form one coherent
Finder/header/status/favicon/social family.

First choose a compact macOS design scale for spacing, radius, semantic typography,
materials, row action chips, pressed/focus/destructive states, and card hierarchy.
Prototype a calmer native-list/toolbar treatment beside the current iOS-like card
stack. Then create optically adjusted 16/32/64/128/512 marks with restrained
material/light and strong small-size silhouettes. Unify the About footer, empty-state
art, website CTA, and public screenshots.

Acceptance: reviewed golden diffs and deterministic layout/accessibility assertions
cover list/editor/settings/Remote Files, focus, long content, 50 profiles, light/dark,
larger text, contrast/transparency/motion settings, pseudolocalization, and current
signed-build identity. Recapture marketing screenshots only from the accepted build.

### RB-029 — Add first-run guidance and error-specific recovery

The empty state does not explain BatchMode, SSH-agent/key prerequisites, first-use
host-key failures, Local Network permission, or how `~/.ssh/config` participates.

Add a short dismissible first-run guide and permanent Troubleshooting surface.
Classify common host-key, authentication, DNS, timeout, refusal, local listener
conflict, and unsupported-interactive-auth failures, then offer safe actions. **Copy
Terminal Test Command** is preferable to weakening host-key or batch policy. Never
imply that RelayBar stores passwords.

Acceptance: every classified fixture gets accurate cause/recovery copy, unknown
errors retain full bounded diagnostics, guidance is keyboard/VoiceOver accessible,
and no action enables password prompts, disables host-key checking, or executes a
shell.

### RB-031 — Remove duplicated information from unnamed profile rows

When `name` is empty, `displayName` falls back to the first rule summary and the next
line repeats it. Multi-rule summaries can also say `via host` before the third line
repeats the host, consuming scarce popover height without adding scan value.

Choose a stable hierarchy for unnamed one-rule, unnamed multi-rule, and named
multi-rule profiles: identity/title, route summary, then state or host only when it
adds information. Keep full values in native help and the inspector.

Acceptance: reviewed light/dark fixtures cover those three hierarchies plus long
host, IPv6, automatic port, multiple failures, and larger text. No identity or
failure information disappears when a duplicate line is removed.

## Performance baselines and measurement targets

Preserve work that is already good: grouping is cached per saved-list mutation;
formatter instances and highlight cache keys are cheap; primary lists are lazy; and
directory-download progress backs off from 250 ms toward 8 s as entry count grows.
Do not reopen withdrawn micro-optimizations without new evidence.

Measure these credible risks before changing them:

- `TunnelStore.waitForControlSocket` polls `fileExists` every 50 ms from a main-actor
  task for each starting profile. A large group can produce hundreds of main-thread
  filesystem checks per second.
- The full 10,000-row Remote Files browser remains mounted behind preview at zero
  opacity. Preview/transfer publication may invalidate it; `previewableEntries`
  repeatedly filters and selected-entry lookup is linear.
- Transfer progress publishes through the top-level model around four times per
  second and may rediff hidden browser/preview surfaces.
- `RemoteDirectoryCache` uses `Dictionary.min` for each over-budget insertion; many
  empty snapshots can turn eviction into repeated linear scans.
- Master stderr dispatches every readable chunk to the main actor and copies a
  bounded buffer; verbose user configuration may create needless churn.

Use signposts and Instruments with large group starts, maximum-size SSH config,
10,000 entries, active transfer, preview navigation, verbose SSH, and large Markdown.
Record before/after main-thread time and dropped frames.

## Manual regression watch list

These are not sufficiently proven by source and must not trigger code changes without
a Mac reproduction:

- Rapid status-item click, outside-click, Escape, action, and reopen sequences may
  expose `.transient` popover close/action ordering. Exercise macOS 13 and current
  macOS, including PR #5 if it lands.
- A starting/retrying row shows a spinner inside a Stop button. Verify hover, cursor,
  focus, help, and VoiceOver make cancellation discoverable; if not, test a progress
  ring around an explicit stop/xmark.
- Group action menus reveal on hover/focus. Verify keyboard discoverability with
  several groups before making them permanently visible.
- `List(selection:)` plus custom accent background may double-paint Remote Files
  selection. Compare appearances and focus states before choosing one treatment.
- The Remote Files launcher is fixed and non-resizable while long errors wrap. Test
  maximum localized errors and larger-text pressure before changing size.
- Explicit preview/sidebar/scroll animations need a real Reduce Motion test.
- The four-segment rule-kind picker may truncate at 380 points under long localization
  or larger text. Compare shorter labels with a menu only after reproduction.
- A material-backed popover, custom action chips, and low-opacity surfaces need
  contrast checks in both appearances; taste is not evidence.

## Product and delight explorations

These ideas fit RelayBar's forwarding-focused identity, but each needs a prototype or
small task spec rather than direct implementation.

### Tunnel operations and speed

- **Tunnel Palette:** menu-scoped fuzzy start/stop/open/copy across profiles and
  recent paths; make any global hotkey opt-in and conflict-aware.
- **Direct keyboard toggles:** optionally map Command-1…9 to the first nine visible
  filtered profiles, with stable ordering, menu discoverability, and conflict checks.
- **Temporary leases:** run for 15 minutes, one hour, until sleep, or a clock time,
  with an obvious extension action.
- **Health beyond process-alive:** opt-in bounded TCP or HTTP checks that distinguish
  SSH connected from destination unavailable.
- **Endpoint recipes:** copy `socks5h://`, `ALL_PROXY=`, Postgres, Redis, or generic
  host/port snippets from typed rule data.
- **One-rule Copy URL:** place the common browser URL directly in the row menu for an
  eligible Local TCP profile instead of burying it in per-rule endpoint actions.
- **Drag/paste/batch import:** drop an SSH command, accept one command per line, or
  support a validated `relaybar://` import link; every route must use the same safe
  transactional review as Quick Add.
- **Per-rule enable/disable:** retain a rule without installing it and show the state
  clearly in editor, copied command, summary, and validation.
- **Route diagrams:** `This Mac :3000 → SSH server → db.internal:5432`, with flags
  secondary.
- **App Intents/Shortcuts:** Start, Stop, Toggle, Start Group, Open Endpoint, and Copy
  Endpoint, with explicit confirmation for broad actions.
- **Retry controls:** after RB-014, consider per-profile policy or a visible global
  pause; never hide an unbounded background loop.
- **Panic stop:** an explicitly taught Option-click or menu action to stop all, with
  no undiscoverable destructive gesture.

### Remote Files and previews

- Multi-selection and a bounded serialized download queue with total count, rate,
  ETA, retry, reveal-in-Finder, and cancellation.
- Markdown find and heading outline; resolve relative Markdown/wiki links only after
  explicit click and within the active remote folder/security bounds.
- Safe drag-out downloads to Finder.
- Upload/edit only as a separate opt-in data-loss/security project with staging,
  overwrite confirmation, safe remote arguments, and a clear read/write mode.

### Character without gimmicks

- A brief directional flow animation only during connect/retry, then static; failure
  stays a distinct static mark. Respect Reduce Motion and avoid perpetual menu-bar
  animation.
- A one-time success ping or opt-in count badge may work if it remains quiet and
  accessible; compare against a dashed connecting variant rather than shipping both.
- Endpoint tokens can show one restrained copy confirmation; automatic ports can
  morph from **Auto** to the assigned value without shifting the row.
- Discoverable Option-click on a primary action could **Start and Copy Endpoint** or
  **Start and Open**; never hide a destructive action behind a modifier.
- Optional soft sound after recovery, group color/icon accents, favorites, and a
  concise group completion summary can add character only when status remains
  understandable without sound or color.

## Visual direction

RelayBar is friendly but visually leans toward an iOS card stack: rounded containers
inside a small popover, circular translucent buttons, tiny tertiary captions, and
several low-opacity borders. A higher-value macOS direction is calmer and denser:

- fewer nested cards and more native list/toolbar hierarchy;
- semantic typography, stronger minimum contrast, and less 9.5 pt tertiary copy;
- obvious hover, pressed, keyboard-focus, default, and destructive states;
- one spacing/radius/type/material scale across popover, editor, Settings, and Remote
  Files;
- one action-chip language for start/stop, browser, and overflow controls;
- a useful inspector for detail instead of forcing every row into three cramped lines;
- restrained push transitions between list/editor/settings and no decorative motion;
- a coherent monochrome/duotone brand in About, empty states, app icon, menu bar, and
  website assets.

Prototype this beside the current layout using long names, IPv6, multi-rule profiles,
failures, 50 profiles, light/dark, larger text, high contrast, and VoiceOver. Do not
treat visual preference alone as proof.

## Test and release gaps

- CI currently provides macOS 15 unit tests and a Release build. Real loopback
  SSH/SFTP, orphan lifecycle, hostile SSH config, long ControlPath, macOS 13, and
  opt-in performance suites are not all gating.
- Add deterministic fake-process regressions to every lifecycle task. Run the real
  unprivileged loopback `sshd` suite on a scheduled or release-gated job.
- Keep macOS 13 manual acceptance active until the documented minimum target has
  current evidence; a macOS 15 build is not a substitute.
- Expand reviewed visual baselines and accessibility-tree/layout assertions before a
  broad visual rewrite. Pixel output alone is not acceptance.
- Require signpost/Instruments evidence for every performance claim and retain the
  repository's healthy habit of withdrawing regressions or sub-1% optimizations.

## Recommended sequence

1. Let the open audit and overlapping feature PRs reach a deliberate merge/close
   decision; do not stack new work on competing implementations.
2. Design RB-010 and RB-013 together, then RB-030; they are one ownership/reaping
   problem.
3. Deliver RB-011 and RB-012 before portability, sync, or broad autostart magnifies
   orphan and storage risk.
4. Fix retry flapping/permanent classification and measured Markdown latency.
5. Deliver validation, imported-option transparency, and diagnostics before adding
   broad automation.
6. Resolve fork identity before enabling or publishing any fork-owned release path.
7. Then scale profile workflows, deepen Remote Files, add onboarding, and execute the
   reviewed visual/accessibility foundation.
