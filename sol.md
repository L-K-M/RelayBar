# RelayBar comprehensive review

Audit date: 2026-08-14
Audited revision: `1faa8d9` (`origin/main` at the start of the review;
[observed green CI run](https://github.com/L-K-M/RelayBar/actions/runs/31840652766))
Scope: application source, tests, fixtures, build and release automation, system and
task specifications, security and privacy documentation, committed screenshots,
assets, and recent repository history.

Document lifecycle: this is the review and implementation ledger requested for the
current pass. Completed entries will not be copied into the durable `ANALYSIS.md`
backlog; remaining work will be consolidated there after the implementation PRs
reach steady state.

## Executive assessment

RelayBar is already much more serious than its small menu-bar footprint suggests.
Its strongest work is below the surface: typed forwarding rules, shell-free SSH and
SFTP invocation, strict option validation, private multiplexing sockets, bounded
diagnostics and previews, cancellation-aware Remote Files operations, and unusually
careful security specifications. The existing test suite is broad, and current
`main` passes both macOS CI jobs.

The main risk is now a mismatch between that strong internal model and the last
10–20% of lifecycle and product behavior. Normal termination does not wait for
children to exit; two process paths retain a PID-reuse race; corrupted preferences
look exactly like an empty app; retry accounting can loop forever after short-lived
"successful" connections; and host SSH configuration can still override some
important process and security assumptions. In the interface, destructive effects
are too quiet, failure state disappears when the popover closes, validation often
amounts to a disabled button, and several compact visual choices work against
accessibility and a premium macOS feel.

The correct product direction is not to become a general SSH client. RelayBar's
advantage is a fast, native, forwarding-focused tool that uses the user's existing
OpenSSH setup. The best investments make that promise more trustworthy, more
observable, and much faster to operate.

## Review method and limits

- Every defect below was checked against source at the audited revision. Source is
  treated as authoritative when a spec disagrees.
- Existing archived tasks and verification were reviewed so fixed work is not
  re-filed. In particular, the SFTP `ProcessBox` PID-reuse fix is real; the remaining
  PID races are in different process owners.
- The current checkout is clean and synchronized with `origin/main`. GitHub Actions
  is green at the audited revision.
- This environment is Linux, so AppKit/SwiftUI execution, Xcode builds, Instruments,
  VoiceOver, and fresh macOS screenshots were not available locally. Findings that
  require those forms of evidence are explicitly deferred instead of being asserted
  as measured facts.
- Current product comparisons use first-party material. Core Tunnel advertises
  wake/network reconnect, advanced option editing, tags, import/export, sync, and
  Shortcuts integration on its [official product page](https://codinn.com/tunnel/)
  and [App Store listing](https://apps.apple.com/us/app/core-tunnel/id1354318707?mt=12).
  Royal TSX documents SSH tunneling, dynamic import, automation, custom colors/icons,
  active-session overviews, and file transfer on its
  [official macOS feature page](https://www.royalapps.com/ts/mac/features). These are
  market signals, not requirements to copy either product or widen RelayBar's trust
  boundary.

## Delivery decisions

`Implement now` means the issue is source-proven, the desired behavior is bounded,
it can be delivered independently, and it does not require an unresolved security,
identity, persistence, or visual-design choice. Each of these entries must use its
own branch and PR.

`Next` means the outcome is high confidence but a complete fix is cross-cutting or
needs Mac/live-SSH evidence, an explicit product choice, or before/after performance
measurement. These are intentionally not candidates for a partial patch.

`Explore` means a promising product or aesthetic idea that should be prototyped and
validated before becoming delivery work.

| ID | Priority | Decision | Outcome |
| --- | --- | --- | --- |
| RB-001 | P0 | Implement now | Force safe SSH master lifecycle/config invariants |
| RB-002 | P1 | Implement now | Create forwarding control paths atomically and within OpenSSH's real path budget |
| RB-003 | P1 | Implement now | Treat invalid UTF-8 SFTP output as an error, never an empty folder |
| RB-004 | P1 | Implement now | Confirm destructive profile deletion and name active-tunnel impact |
| RB-005 | P1 | Implement now | Make tunnel-row status, browser, and truncated text affordances truthful |
| RB-006 | P1 | Implement now | Let users cancel the initial Remote Files connection/open |
| RB-007 | P1 | Implement now | Expose failure attention in the status item and accessibility value |
| RB-008 | P1 | Implement now | Give principal form controls stable accessibility labels |
| RB-009 | P1 | Implement now | Restore updater/privacy/security/task-index documentation truth |
| RB-010 | P0 | Next | One termination coordinator that waits, reaps, and safely escalates all children |
| RB-011 | P0 | Next | Crash/force-quit orphan reconciliation |
| RB-012 | P0 | Next | Corruption-safe, recoverable profile and server persistence |
| RB-013 | P0 | Next | Bound control/startup timeouts even when children ignore `SIGTERM` |
| RB-014 | P0 | Next | Prevent infinite reconnect loops after short-lived running phases |
| RB-015 | P1 | Next | Preserve master stderr reliably on fast exit |
| RB-016 | P1 | Next | Bound imported and persisted configuration complexity |
| RB-017 | P1 | Next | Fix the measured large-Markdown bottleneck and main-thread highlighting |
| RB-018 | P1 | Next | Move and cache SSH-config discovery off the main actor |
| RB-019 | P1 | Next | Make editing, quitting, and draft abandonment explicit and recoverable |
| RB-020 | P1 | Next | Replace disabled-save guessing with field-level validation |
| RB-021 | P1 | Next | Expose and safely edit imported SSH options |
| RB-022 | P1 | Next | Add full diagnostics, history, and actionable failure recovery |
| RB-023 | P1 | Next | Build scalable, keyboard-first profile management |
| RB-024 | P1 | Next | Add opt-in start, wake, and network recovery policies |
| RB-025 | P1 | Next | Bring Remote Files navigation and list semantics up to macOS expectations |
| RB-026 | P1 | Next | Complete the accessibility, typography, motion, and localization foundation |
| RB-027 | P1 | Next | Resolve fork identity and update authority |
| RB-028 | P2 | Next | Rebuild visual QA and redraw the app icon family |
| RB-029 | P2 | Next | Add onboarding and error-specific troubleshooting |
| RB-030 | P1 | Next | Keep restart behind retiring listener ownership |
| RB-031 | P2 | Next | Remove duplicated information from unnamed profile rows |

## Implement-now entries

### RB-001 — Force safe SSH master invariants

Priority: P0 security/correctness
Confidence: high
Disposition: implement now in its own PR

The forwarding master intentionally reads the user's normal SSH configuration, but
its command line does not currently force every invariant RelayBar relies on.
`TunnelStore.masterArguments` sets batch mode, clears configured forwards, and turns
off control persistence, but it does not force foreground execution, disable local
commands, disable tun devices, disable agent/X11 forwarding, or prevent a configured
`GatewayPorts` value from changing remote-bind semantics. A forgotten or hostile
per-host config can therefore make the child detach, execute `LocalCommand`, or gain
authority that is neither typed nor visible in RelayBar.

Evidence: `Sources/RelayBar/TunnelStore.swift:399-423`; compare the claimed boundary
in `docs/system-specs/shared/security-boundaries.md:3-16`.

Delivery:

- Force `ForkAfterAuthentication=no`, `PermitLocalCommand=no`, `Tunnel=no`, and
  `GatewayPorts=no`, plus agent- and X11-forwarding disablement, on the master.
- Preserve intended config-based authentication, identity, host-key, ProxyJump, and
  proxy behavior.
- Document exactly which SSH-config classes RelayBar overrides.

Acceptance:

- Argument tests prove every invariant is present exactly once.
- A hostile temporary SSH config evaluated with real `ssh -G` cannot enable
  forking, local commands, tun, agent/X11 forwarding, or gateway ports.
- Normal aliases, identity files, host-key policy, and jump hosts remain usable.

### RB-002 — Atomically create correctly budgeted forwarding control paths

Priority: P1 security/reliability
Confidence: high
Disposition: implement now in its own PR

The forwarding path uses a generated 12-hex-character directory name, checks whether
it exists, removes it if so, then creates it. That check/remove/create sequence is not
atomic, despite the system security spec claiming atomic creation. It also accepts a
final Unix-socket path up to 103 bytes without reserving OpenSSH's 17-byte temporary
mux-listener suffix. The Remote Files master already implements the correct
`mkdtemp`, suffix, and NUL budget.

Evidence: `Sources/RelayBar/TunnelStore.swift:952-972` versus
`Sources/RelayBar/RemoteFileSSHSession.swift:169-178,472-500` and
`docs/system-specs/shared/security-boundaries.md:13`.

Delivery:

- Reuse one private-control-location primitive for both process owners, or give the
  forwarding owner an equivalent atomic implementation without divergent constants.
- Keep the directory short, private (`0700`), uniquely owned, and removable only
  through its validated prefix.
- Reserve OpenSSH's temporary suffix and Darwin's terminating NUL.

Acceptance:

- Boundary tests cover the longest valid socket path and first invalid path under a
  deliberately long temporary directory.
- Parallel creation produces distinct directories without pre-removal.
- A created directory is `0700`; rejected paths leave no directory behind.

### RB-003 — Reject malformed SFTP text instead of showing an empty folder

Priority: P1 data integrity/UX
Confidence: high
Disposition: implement now in its own PR

`SFTPRemoteFileService.readString` maps read errors and UTF-8 decode failures to the
same empty string. If a successful SFTP listing contains invalid UTF-8—for example,
from a filename in another byte encoding—the parser can report a successful empty
folder. That is materially different from "RelayBar could not represent this
listing" and can mislead users about remote contents.

Evidence: `Sources/RelayBar/SFTPRemoteFileService.swift:757-764,860-876`.

Delivery:

- Preserve read/decode failure as a typed malformed-response error for command
  output.
- Keep diagnostics loss-tolerant and bounded so a malformed error stream can still
  produce a useful safe message.

Acceptance:

- An invalid-byte listing produces a clear error and never a successful empty list.
- A genuinely empty, valid UTF-8 listing remains a successful empty list.
- Read failures and size-limit failures retain distinct messages.

### RB-004 — Confirm profile deletion and disclose connection impact

Priority: P1 destructive UX
Confidence: high
Disposition: implement now in its own PR

The profile row's destructive menu item calls `store.delete` immediately. Deletion
also stops an active tunnel. Remote Files already confirms removal of a saved host,
so the two destructive actions are inconsistent.

Evidence: `Sources/RelayBar/RelayBarRootView.swift:355-420`,
`Sources/RelayBar/TunnelStore.swift:201-207`, and the existing confirmation at
`Sources/RelayBar/RemoteFilesView.swift:167-177`.

Delivery:

- Require a confirmation naming the profile.
- If active/starting/retrying, say explicitly that deletion will stop the connection.
- Keep Cancel as the safe/default route and make the destructive button accessible
  by keyboard and VoiceOver.
- A future undo banner would be welcome, but confirmation is the bounded fix here.

Acceptance:

- Invoking Delete alone changes neither storage nor runtime state.
- Confirm deletes exactly the named profile and stops it when active; Cancel and
  Escape preserve it.
- Two similarly named profiles cannot be confused in the dialog.

### RB-005 — Make compact tunnel-row affordances honest and inspectable

Priority: P1 UX/accessibility
Confidence: high
Disposition: implement now in its own PR

Three small row-level choices currently miscommunicate behavior:

- `Retrying in Ns` displays the original delay for the entire wait; it is not a
  countdown.
- The Safari glyph is shown even though `NSWorkspace.open` uses the user's default
  browser.
- Name, route summary, host, and error text are one-line truncated without hover
  access to the full value; the ellipsis menu lacks a specific accessible label.

Evidence: `Sources/RelayBar/RelayBarRootView.swift:308-360,418-440,535-543` and
`Sources/RelayBar/TunnelStore.swift:896-909`.

Delivery:

- Use truthful non-countdown retry copy in this bounded fix; an absolute-deadline
  countdown can be added later only if it updates visible rows without whole-store
  churn or VoiceOver announcements every second.
- Use a browser-neutral system symbol and say "default browser" in help where useful.
- Add full-value help to truncated primary, summary, and status text; name the row
  actions menu for assistive technology.

Acceptance:

- Retry text never claims a remaining duration it does not calculate.
- No Safari-specific icon or label is used for a default-browser action.
- Every truncated row string is recoverable by hover and all row actions have stable
  accessibility names.

### RB-006 — Add cancellation to the initial Remote Files open

Priority: P1 responsiveness/control
Confidence: high
Disposition: implement now in its own PR

The launcher replaces Open with a spinner and disables the button while connecting.
There is no Cancel action on that screen. Initial SSH-master readiness can wait up to
120 seconds, so the only visible escape hatch is closing the whole window. Folder
navigation already gives Back a cancellation meaning, making the first operation the
odd one out.

Evidence: `Sources/RelayBar/RemoteFilesView.swift:57-157` and
`Sources/RelayBar/RemoteFilesModel.swift:374-399,637-653,655-775`.

Delivery:

- Turn the launcher's primary action into an explicit Cancel while its open is
  pending, with a clear accessibility label and Escape support.
- Invalidate the load generation, cancel the waiter, retire a no-longer-needed
  session, reset loading state, and remain on the launcher without an error.
- Do not let a late result navigate to the browser after cancellation.

Acceptance:

- A suspended initial open cancels promptly and stays on the launcher.
- A late success/failure from the canceled generation publishes nothing.
- A new Open after cancellation starts cleanly and succeeds.
- Browser navigation and transfer cancellation behavior remain unchanged.

### RB-007 — Give the status item an issue state and meaningful accessibility value

Priority: P1 observability/accessibility
Confidence: high
Disposition: implement now in its own PR

The status icon is only filled or unfilled based on `runningCount`; retry exhaustion
is therefore indistinguishable from everything intentionally stopped while the
popover is closed. The button's accessibility title is always just `RelayBar`.

Evidence: `Sources/RelayBar/RelayBarApp.swift:103-140,191-210` and
`Sources/RelayBar/TunnelStore.swift:88-90,878-892`.

Delivery:

- Derive a small status summary with stopped, active, and issue attention states;
  issue wins when any profile is failed, while counts remain available to the UI.
- Use a distinct static template symbol/fallback for issue attention—no perpetual
  animation or color-only meaning.
- Update the status button's accessibility value/description with active and failed
  counts whenever the image state changes or counts change within the same state.

Acceptance:

- Zero active/zero failed, active, and failed fixtures produce distinct summaries.
- A failed profile changes the closed-popover icon and VoiceOver description.
- Multiple counts pluralize correctly; status changes do not recreate the item or
  disturb its autosaved position.

### RB-008 — Give principal form controls stable accessibility labels

Priority: P1 accessibility
Confidence: high
Disposition: implement now in its own PR

Several visible field labels are sibling `Text` views rather than programmatic names.
VoiceOver can therefore fall back to placeholders such as an example hostname or
path, whose meaning changes once the field contains data.

Evidence: `Sources/RelayBar/TunnelEditorView.swift:160-188,866-887` and
`Sources/RelayBar/RemoteFilesView.swift:57-75,580-630`.

Delivery:

- Give Profile Name, SSH Host, Remote Path, saved-host Name, and saved-host SSH Host
  explicit, stable accessibility labels and useful optional hints.
- Audit the forwarding-rule fields reached by the same reusable wrapper and label
  any control whose purpose currently depends on nearby visual text.

Acceptance:

- Accessibility inspection exposes purpose-based labels independent of placeholder
  and current value.
- Empty and populated forms announce the same field names.
- Labels do not duplicate into noisy repeated announcements.

### RB-009 — Restore updater, privacy, security, and active-task truth

Priority: P1 documentation/product trust
Confidence: high
Disposition: implement now in its own PR

The security review states that no update SDK ships, but Sparkle 2.9.4 is linked and
configured. The privacy policy does not disclose manual or opted-in scheduled feed
requests. Settings calls the switch `Automatic Updates` even though installation is
never automatic. The task index omits active Task 034, and the system-spec index's
review date predates several documented behaviors.

Evidence: `docs/SECURITY_REVIEW.md:73-105`, `PRIVACY.md:1-13`,
`Sources/RelayBar/SettingsView.swift:110-139`, `Packaging/Info.plist:35-49`,
`docs/task-specs/README.md:32-38`, and `docs/system-specs/README.md:1-4`.

Delivery:

- Describe Sparkle, HTTPS feed checks, EdDSA/feed signing, relaunch gating, normal
  server-visible request metadata, and the fact that no analytics/system profile is
  submitted.
- Rename the setting to `Automatically Check for Updates` while retaining clear copy
  that installation requires a user decision.
- Add Task 034 to the active index and refresh the system-spec audit date without
  rewriting historical verification records.

Acceptance:

- UI, security review, privacy policy, Info.plist, and system specs describe the same
  check/install behavior.
- The active index lists every task directly under `docs/task-specs/`.
- No claim implies that Sparkle, network access, automatic installation, or telemetry
  is absent/present contrary to source.

## Next work

### RB-010 — Coordinate, await, and safely reap every normal shutdown

Priority: P0 lifecycle/security
Confidence in outcome: high; implementation readiness: design required

`applicationShouldTerminate` normally returns `.terminateNow`.
`applicationWillTerminate` then closes Remote Files and calls `stopAll`, but the app
cannot wait for the delayed escalation and cleanup tasks. A cooperative SSH child
usually exits, while a stubborn/slow one can survive app exit with live listeners.
The forwarding master and Remote Files master also check `Process.isRunning` and then
signal a numeric PID later, retaining the same check-to-signal PID-reuse race that
archived Task 008 fixed only for SFTP children.

Do not solve this piecemeal. Introduce one serialized child owner/coordinator for
forwarding masters, control helpers, the Remote Files master, and SFTP children. Every
normal termination route should return `.terminateLater`, stop accepting work, send
`SIGTERM`, await ownership-confirmed exit, escalate once without a recycled-PID gap,
clean artifacts, and reply to AppKit. Integrate Sparkle's deferred relaunch gate and
termination reentrancy.

Acceptance: footer Quit, Cmd-Q, system shutdown/logout, Remote Files transfer, update
relaunch, cooperative children, stubborn children, and concurrent helpers all leave
zero owned children and zero private control directories. No signal occurs after a
child is reaped.

### RB-011 — Reconcile orphaned tunnels after crash or force-quit

Priority: P0 lifecycle/recovery
Confidence in outcome: high; implementation readiness: threat design required

A crash or `SIGKILL` cannot run termination cleanup. Foreground masters have standard
input/output on `/dev/null` and `ControlPersist=no` does not bind their lifetime to
RelayBar's process, so a live invisible forward can survive and later look like an
unexplained port conflict.

Persist a private, minimal ownership manifest with a launch nonce, control location,
and safely verifiable process identity. On startup, inspect only permission-checked
app-owned artifacts; retire a positively identified orphan through its private
control socket, or present a recovery choice. Never kill from an unverified stale
PID. Garbage-collect dead directories idempotently.

Acceptance: force-kill with a live real forward, relaunch, and prove the listener is
safely retired or explicitly recovered. Crafted directories, symlinks, other-user
artifacts, and recycled PIDs remain untouched.

### RB-012 — Make saved configuration corruption-safe and recoverable

Priority: P0 data integrity
Confidence in outcome: high; implementation readiness: storage/migration design required

`TunnelStore.init` decodes the complete `savedTunnels.v2` array with `try?`; any
failure silently falls back to legacy data or `[]`. One corrupt record can therefore
make every profile disappear, and a later save can overwrite recoverable bytes.
Remote Files saved/recent record arrays have the same all-or-nothing pattern.

Move toward an atomic versioned Application Support document or equivalent backup
scheme. Preserve undecodable bytes, block ordinary empty-state writes, offer a
recovery/export surface, keep timestamped backups, salvage individually valid records
where safe, and report rejected records. Exported metadata may expose hostnames and
identity paths, so its privacy UX is part of the design.

Acceptance: truncated JSON, one unknown enum, one invalid record, duplicate IDs, and
a failed migration never silently erase valid siblings or overwrite the last good
payload. Backup restore and versioned export/import round-trip all supported fields.

### RB-013 — Make timeout actually mean bounded

Priority: P0 correctness
Confidence in defect: high; implementation readiness: depends on RB-010

`scheduleControlTimeout` and `failStartup` call only `process.terminate()` and wait
for the termination handler. A control helper or startup master that ignores
`SIGTERM` can remain alive forever, leaving the continuation unresolved and the
profile stuck Starting. The current timeout fixture exits on TERM, so it does not
exercise this case.

Route timeout, cancellation, rollback, stop, and quit through the RB-010 child owner
with exactly-once completion. Add stubborn master and stubborn control-helper
fixtures. A timeout must lead to a bounded kill/reap, rollback, then retry/failure—not
just a timeout string appended to a still-running process.

### RB-014 — Prevent endless retry flapping

Priority: P0 reliability/energy
Confidence in defect: high; implementation readiness: retry policy decision required

After every successful rule installation, `retryAttempts[id]` resets immediately to
zero. A master that reaches Running and exits seconds later therefore retries as
attempt 1 forever, defeating the documented ten-attempt ceiling and potentially
creating an endless one-second authentication/network loop.

Reset the budget only after a documented stability window, or count consecutive
short-lived runs. Key any timer by launch generation, handle sleep/wake explicitly,
and ensure a user stop cancels it. Acceptance needs a deterministic flapping fixture
that reaches Failed and a stable fixture that earns a reset.

### RB-015 — Preserve final SSH diagnostics on fast exit

Priority: P1 diagnostics
Confidence in defect: high; implementation readiness: process-owner design preferred

Master stderr and process termination independently enqueue main-queue work. Exit
classifies the current buffer and clears the handler without a final owned drain, so
fast failures can lose the actionable last lines. If the bounded buffer starts in the
middle of a UTF-8 scalar, strict decoding discards the entire message. An already
queued late append can also arrive after cleanup.

Give stderr one serialized owner, detach then drain on exit, key appends to the exact
process/generation, and decode bounded diagnostics loss-tolerantly or at a valid
scalar boundary. Repeated immediate-exit tests should always preserve final lines,
including a multibyte truncation boundary.

### RB-016 — Bound importer, profile, and persistence complexity

Priority: P1 availability/security
Confidence in problem: high; implementation readiness: choose product limits

Command bytes, token count, option count, rules per profile, total profile count,
several visible strings, and total persisted payload are not consistently bounded.
A huge paste or tampered defaults payload can drive excessive parsing, persistence,
validation, and thousands of SwiftUI editor rows.

Choose and document realistic exact limits; validate before mutating the editor and
again before publishing decoded storage. Boundary and one-over tests must prove fast,
transactional rejection with a specific message.

### RB-017 — Optimize the measured Markdown bottleneck

Priority: P1 performance
Confidence in bottleneck: measured; implementation readiness: profile on macOS first

Repository evidence records roughly 1.0 second in Release for
`ObsidianMarkdownCompatibility.renderSource` on a 776 KB fixture—about 150× the work
an earlier micro-optimization targeted. The 2 MiB supported limit permits worse.
The pipeline performs repeated complete scans and per-line `[Character]`
materialization. Separately, a cache-miss syntax highlight can run JavaScriptCore
synchronously from `MarkdownCodeBlock.body` on the main thread.

Add signposts for transform, parse, highlight, and first render; benchmark 100 KB,
776 KB, and maximum-size representative documents; consolidate lexical passes or skip
absent enrichments; and precompute highlighting off-main with cancellation and an
aggregate budget. Preserve the entire security/compatibility fixture corpus
byte-for-byte. Target a material improvement (3× is a useful bar) and a measured main
thread frame budget, not an unsubstantiated "faster" claim.

### RB-018 — Stop rereading SSH config on the main actor

Priority: P1 responsiveness
Confidence in source cost: high; user-visible severity needs measurement

`RemoteServerCatalog` is `@MainActor`, and every `servers(from:)` call synchronously
reads/parses up to 1 MiB of `~/.ssh/config`. It runs during model creation and again
after successful navigation refreshes. Cache results by file identity/modification
and perform bounded I/O/parsing away from the main actor. Support for `Include` should
be a separate permission-aware, cycle-safe, glob- and aggregate-bounded task.

Acceptance: an injected slow maximum-size config does not stall the launcher;
unchanged files are not reread; replacement, modification, deletion, and permission
failure invalidate deterministically.

### RB-019 — Make lifecycle-changing user decisions explicit

Priority: P1 trust/UX

Three paths discard or stop more than their labels imply:

- normal Quit stops active tunnels without naming the count or giving a safe defer;
- saving a connection-changing edit stops an active profile and leaves it stopped;
- Back/Cancel abandons a potentially long multi-rule draft without dirty-state
  protection, and transient-popover closure loses it.

After RB-010 supplies real shutdown semantics, use one quit decision for footer Quit,
Cmd-Q, and system termination. Offer `Stop N and Quit` and Cancel. Active edits should
offer `Save & Restart`, `Save & Stop`, and Cancel; metadata-only edits remain live.
Pristine drafts leave immediately, dirty drafts offer Discard/Keep Editing, and
popover closure preserves the draft for the session.

### RB-020 — Replace disabled-save guessing with validation users can act on

Priority: P1 usability/accessibility

`builtTunnel` can reject hosts, ports, Unix paths, masks, listener conflicts, reverse
policies, or unsafe options, but the visible result is usually only a disabled Save
button. Introduce typed validation results, inline messages beside the responsible
field/rule, an offscreen error summary, and first-invalid focus/scroll. Duplicate
listeners should name both rule numbers. A disabled primary action must never be the
sole explanation.

### RB-021 — Make imported SSH options inspectable and editable

Priority: P1 transparency/power-user UX

Edit shows only `N imported SSH option values will be preserved`. The user cannot see
or change port, jump host, identity path, address family, or allowed `-o` values, even
though they materially define the connection. Add safe structured fields with
contextual help, removal/editing, a redacted source-equivalent command preview, and a
transactional re-import route on Edit. Do not turn this into an arbitrary ssh_config
editor or admit command-executing options.

### RB-022 — Add a bounded inspector, event history, and recovery actions

Priority: P1 observability/polish

Tunnel errors are one row line; Remote Files strips are capped; current phase replaces
the sequence that led there. Add a profile inspector with phase, uptime, assigned
automatic ports, all rules, bounded full error, retry timeline, safe effective
connection metadata, Retry/Edit, and Copy Diagnostics. Keep a session-bounded event
history for start, connected, retry, recovery, stop, failure, update interruption,
and Remote Files session events. Redact secrets and never include private-key content
or remote file data. Optional failure/recovery notifications come later, with consent
and deduplication.

### RB-023 — Make large profile sets fast to operate

Priority: P1 productivity

The fixed 380×440 popover shows only a few large cards and has no quick filter,
global lifecycle action, duplicate, reorder, favorites, compact density, or list
selection model. Deliver these as separate small tasks:

1. Command-F/Command-K filtering by name, group, host, and endpoint.
2. Keyboard selection with Space toggle, Return edit/open, and named row/group menus.
3. Global Start All/Stop All with an exact-target confirmation where destructive.
4. Duplicate Profile with regenerated profile/rule IDs.
5. Persistent reorder, favorites/pinning, collapsible groups, and optional compact
   rows.
6. Adaptive popover height within the active screen's safe area.

A 50–100-profile fixture should remain responsive; filtering and ordering must never
alter lifecycle identity.

### RB-024 — Add opt-in autostart and network-aware recovery

Priority: P1 reliability/product parity

Launch at Login deliberately starts no profiles. There is no per-profile start policy
and no wake/network observer; keepalives can take roughly 90 seconds to discover a
dead path. Add `Start when RelayBar opens`, default off, then explicitly define update
relaunch, wake, VPN, captive-portal, and rapid path-churn behavior. Debounce network
events and restart only profiles whose desired-active policy requires it. Standing
consent must be visible and reversible.

### RB-025 — Make Remote Files feel like a native focused browser

Priority: P1 productivity/visual quality

Deliver independently:

- A real path control: Up/Command-Up, Command-L, Copy Path, clickable ancestors, and
  optional explicitly saved recent server/path pairs.
- Native column headers and client-side Name/Date/Size/Kind sorting and Command-F
  filtering over the already-loaded snapshot only.
- Explicit symlink semantics and visual distinction.
- First-row/list focus after opening so arrows, Space, Return, and Command-Down work
  immediately.
- A launcher/window that keeps the user's position and anchor while resizing rather
  than recentering on state changes.
- An inactivity watchdog for hung listings and progress-reset timeouts for transfers.
- A tightly bounded preview LRU plus one-neighbor prefetch, image Fit/Actual Size/zoom,
  and separately bounded plain-text/JSON/YAML/log/PDF previews.

Measure hidden-browser invalidation, repeated `previewableEntries` scans, and transfer
progress publication with 10,000 entries before caching or splitting observation.
Preserve session-only path privacy unless the user opts into path recents.

### RB-026 — Finish the macOS accessibility and localization foundation

Priority: P1 accessibility/quality

There are more than 100 fixed-point font calls across core surfaces, including
9.5–10.5 pt tertiary copy. Connection state leans on a tiny color dot; async failures
and transfer completion are not announced; explicit sidebar/scroll animations ignore
Reduce Motion; the main menu and keyboard routing are incomplete; and there is no
String Catalog despite long-localization claims.

Migrate deliberately to semantic/relative text styles, strengthen contrast, add
non-color state labels/traits and one-shot async announcements, honor Reduce Motion
and Increase Contrast, complete standard shortcuts (`Command-N`, `Command-,`, Escape,
default Save), and introduce plural-aware localization with pseudolocalized/RTL
fixtures. Verify with VoiceOver, Accessibility Inspector, keyboard-only operation,
maximum text size, high contrast, reduced transparency/motion, light/dark appearance,
and long localization.

### RB-027 — Choose one coherent fork/update identity

Priority: P1 distribution trust
Blocked on owner decision

The README says this is an L-K-M fork that publishes no releases and exists for a
fork-specific status-item fix. The app retains `com.lx2026.RelayBar`, the upstream
Sparkle feed/public key, upstream website/repository links, and upstream release
documentation. A future upstream update can therefore replace the fork build and the
change that motivated it.

Choose one model: an upstream-tracking patch build, an independently maintained fork,
or changes intended to merge upstream. An independent product needs fork-owned bundle
and update identity, feed, signing key, links, provenance, and a migration plan. An
upstream-updatable patch build must disclose that updates replace fork modifications
and should not enable them until equivalent fixes are upstream. About/diagnostics
should identify channel, owner, version/build, and commit.

### RB-028 — Rebuild visual QA and the icon family

Priority: P2 visual quality/release hygiene

Committed tunnel screenshots omit the current Settings gear and the editor image
shows a layout defect already fixed. The snapshot harness mostly checks that an image
was written, not that it matches a reviewed golden. It does not cover focus, larger
text, contrast/transparency/motion settings, pseudolocalization, or VoiceOver.

The 1024 icon is an opaque, high-glow blue tile; at 16 points the opposed arrows
collapse toward a bright dash. Finder icon, header mark, status item, favicon, social
art, and the website CTA icon are inconsistent—the CTA asset is only the gradient
background.

Create an optically adjusted family for 16/32/64/128/512 points with a coherent arrow
motif, proper macOS silhouette/padding, restrained material/light, and strong small
sizes in both appearances. Add reviewed golden diffs and deterministic layout/AX
assertions for core states and pressure variants. Recapture all public screenshots
only on a signed/identified current build.

### RB-029 — Add first-run guidance and error-specific recovery

Priority: P2 activation/support

The empty state does not explain BatchMode, SSH-agent/key prerequisites, first-use
host-key failures, Local Network permission, or how `~/.ssh/config` participates.
Add a short first-run walkthrough and permanent Troubleshooting surface. Classify
common host-key, authentication, DNS, timeout, refusal, local-port-conflict, and
unsupported-interactive-auth errors and offer safe recovery. A `Copy Terminal Test
Command` action is preferable to weakening host-key or batch policy. Never imply that
RelayBar stores passwords.

### RB-030 — Keep restart behind retiring listener ownership

Priority: P1 reliability
Confidence in race: high; implementation readiness: depends on RB-010

`stop` removes the old launch from runtime ownership immediately, even though a
stubborn master can keep its TCP or Unix listeners for the five-second grace period.
An immediate Restart can therefore install the same listeners on a new master before
the old owner is reaped, producing avoidable address-in-use failure and retry. This is
separate from the launch-generation isolation already delivered by Task 007.

Retain a per-profile retiring-launch barrier. A replacement may authenticate in
parallel only if it cannot install listeners until the prior owner is proven reaped.
Acceptance needs a listener-holding stubborn fixture that restarts without transient
address-in-use failure, duplicate masters, or stale cleanup affecting the replacement.

### RB-031 — Remove duplicated information from unnamed profile rows

Priority: P2 information design
Confidence in defect: high; implementation readiness: choose and snapshot hierarchy

When `name` is empty, `displayName` falls back to the first rule summary and the next
line renders that summary again. A multi-rule summary already says `via host`, then
the third line repeats `via host`. The result uses precious popover space without
adding scan value.

Choose a stable hierarchy for unnamed one-rule, unnamed multi-rule, and named
multi-rule profiles—for example identity/title, route summary, then state/host only
when not already present. Verify all three fixtures in light/dark and with long host,
IPv6, automatic port, and failure text before changing the fallback globally.

## Measured-before-changing observations

These source patterns are credible performance risks, but only the Markdown item has
current timing evidence. Instrument them before adding caches or state complexity:

- `TunnelStore.waitForControlSocket` performs 50 ms `fileExists` polling from a
  main-actor task for up to 12 seconds per profile. Starting a large group can create
  hundreds of main-thread filesystem checks per second.
- The full 10,000-row Remote Files browser remains mounted behind preview with
  opacity zero. Preview and transfer publications can still invalidate it;
  `previewableEntries` filters the whole listing on every access and selected-entry
  lookup is linear.
- Transfer progress publishes through the top-level model roughly four times per
  second, potentially rediffing browser and preview surfaces.
- `RemoteDirectoryCache` finds the least-recent snapshot with `Dictionary.min` on
  every over-budget insertion. The worst case is many empty snapshots (each charged
  one entry), where eviction becomes repeated linear scans.
- Master stderr dispatches every readable chunk to the main actor and copies a
  bounded buffer. A user config enabling very verbose SSH output may create needless
  main-thread churn even though memory stays bounded.

Use signposts and Instruments with large group starts, a maximum-size SSH config, a
10,000-entry listing, active transfer progress, preview navigation, and verbose SSH.
Keep only changes that materially improve main-thread time or dropped frames; the
repository has correctly withdrawn sub-1% micro-optimizations before.

## Manual regression watch list

These are not source-proven defects and should not trigger code changes without a
Mac reproduction:

- The status-item PR history calls out a possible `.transient` popover close/action
  ordering race when the icon is clicked while its popover is open. Exercise rapid
  click, outside-click, Escape, and reopen sequences on macOS 13 and current macOS.
- A starting/retrying row shows a spinner inside a button whose action is Stop. Test
  whether hover, cursor, focus, help, and VoiceOver make cancellation discoverable;
  if not, use a progress ring around a stop/xmark rather than a passive spinner.
- Group action menus intentionally reveal on hover/focus. Verify keyboard focus and
  discoverability with several groups before making them permanently visible.
- The Remote Files launcher is fixed and non-resizable while long errors can wrap;
  test maximum localized error and larger-text pressure before choosing a new size.
- Explicit preview scrolling/sidebar animations need a real Reduce Motion check;
  do not infer system behavior from SwiftUI source alone.

## Product and delight backlog

These ideas fit the product and are the review's `Explore` items. Each should begin
with a prototype or short task spec rather than direct implementation.

### Tunnel operations

- **Tunnel Palette.** A global or menu-scoped fuzzy command palette for start, stop,
  open, and copy. Keep the global hotkey opt-in and conflict-aware.
- **Temporary tunnel leases.** Run for 15 minutes, one hour, until sleep, or until a
  chosen clock time, with a visible extension action. This is useful and
  security-friendly.
- **Health beyond process-alive.** Optional TCP or HTTP checks that distinguish
  `SSH connected` from `service unavailable`, without redefining SSH success.
- **Endpoint recipes.** Copy `socks5h://`, `ALL_PROXY=`, Postgres, Redis, or generic
  host/port snippets from visible typed rule data.
- **Port conflict assist.** Explain the owning local process where permitted and offer
  a safe automatic-port alternative; never silently kill or rebind.
- **Drag/paste import.** Drop or paste an `ssh -L/-R/-D` command onto the popover or
  status item, then show the same safe import review before saving.
- **Rule route diagrams.** A tiny plain-language diagram such as `This Mac :3000 →
  SSH server → db.internal:5432`, with the technical flag form secondary.
- **App Intents/Shortcuts.** Start, Stop, Toggle, Start Group, Open Endpoint, and Copy
  Endpoint, with explicit confirmation for broad actions.

### Remote Files and previews

- Multi-selection and a bounded queued download manager with total count, rate, ETA,
  retry, reveal, and cancellation.
- Markdown find and heading outline; explicit-click resolution of relative Markdown
  and wiki links within the active remote folder using the existing preview bounds.
- Safe drag-out downloads to Finder. Upload/edit should remain a separate security
  and data-loss decision, not an incidental extension of read-only browsing.
- Favorites for explicit server/path pairs with a prominent privacy choice and Clear
  History.

### Character without gimmicks

- A brief directional flow animation only during connection/retry, then completely
  static. Failure uses a distinct static mark. Respect Reduce Motion and never run a
  perpetual menu-bar animation.
- Endpoint tokens can give one restrained copy confirmation; automatic `Auto` ports
  can morph to the assigned value after success.
- Option-click on a primary profile action could `Start and Copy Endpoint` or `Start
  and Open`, but only with discoverable help and no hidden destructive behavior.
- Group color/icon accents and favorites can improve scanning, provided status never
  depends on color and the popover avoids becoming a wall of colored cards.

## Visual direction

The current UI is friendly and coherent, but it leans toward an iOS card stack:
rounded containers inside a small popover, circular translucent icon buttons, tiny
tertiary captions, and several low-opacity borders/fills. A higher-value macOS
treatment would be calmer and more information-dense:

- fewer nested cards and more native list/toolbar hierarchy;
- semantic typography with a stronger minimum contrast and less 9.5 pt tertiary copy;
- obvious hover, pressed, keyboard-focus, and destructive states;
- one consistent spacing/corner-radius/type scale across popover, editor, Settings,
  and Remote Files;
- a useful inspector for detail instead of forcing every row to carry three cramped
  lines;
- restrained motion tied to a meaningful transition, never decoration that runs.

Prototype this direction beside the current layout and compare it under real content:
long names, IPv6, multi-rule profiles, failures, 50 profiles, light/dark, larger text,
high contrast, and VoiceOver. Do not treat taste alone as proof that a redesign is
better.

## Test and release gaps

- CI currently runs macOS 15 unit tests and a Release build. Real loopback SSH/SFTP,
  process-orphan lifecycle, hostile ssh_config, long ControlPath, and opt-in
  performance suites are not gating.
- Add deterministic fake-process regressions to each lifecycle PR. Run the real
  unprivileged loopback `sshd` suite on a scheduled or release-gated job.
- Add Instruments/signpost evidence for any stutter claim. In particular, measure
  hidden 10,000-row browser invalidation, preview filtering, main-actor SSH-config
  work, and syntax highlighting before claiming a speedup.
- Keep macOS 13 manual acceptance active until the documented target has current
  evidence. A macOS 15 CI build does not substitute for it.
- Every implemented entry must update its affected system spec, run warnings-as-errors
  tests/builds, pass `git diff --check`, and record any required visual, accessibility,
  security, or live-SSH evidence before its task spec is archived.

## Recommended sequence

1. Ship RB-001 through RB-009 as independent, low-coupling PRs.
2. Design RB-010 and RB-013 together; they are one child-ownership problem, not two
   opportunities to add more delayed numeric-PID signalling.
3. Deliver RB-012 before adding sync/import convenience, so portability does not
   amplify a fragile storage format.
4. Fix retry flapping and large-Markdown latency, with measured evidence.
5. Deliver diagnostics/validation/imported-option transparency before broad feature
   expansion.
6. Resolve fork identity before any release or automatic-check rollout.
7. Then invest in scalable workflows, Remote Files polish, onboarding, and the visual
   identity refresh.
