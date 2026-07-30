# Task 026 — Make Remote Files Navigation Responsive

Status: Complete

Created: 2026-07-29

Accepted: 2026-07-30

## Outcome

Make folder navigation and preview startup feel responsive on high-latency SSH
connections without changing Remote Files' exact-path, read-only boundary.

Today `SFTPRemoteFileService.list` starts a new batch `/usr/bin/sftp` process
for every folder. Each uncached click therefore repeats connection setup,
key exchange, authentication, subsystem startup, and listing. OpenSSH
[`ControlMaster`](https://man.openbsd.org/ssh_config#ControlMaster) exists to
share multiple sessions over one network connection, while Apple's
[loading guidance](https://developer.apple.com/design/human-interface-guidelines/loading)
recommends showing useful content as soon as possible and loading updates in
the background.

Keep the current bounded, one-operation SFTP subprocesses, but route them
through one app-owned SSH multiplexing master for the active Remote Files
connection. Combine that transport reuse with a session-only directory cache,
stale-while-revalidate navigation, and feedback that reacts immediately.

## Delivery Boundary

### Included

- One private SSH multiplexing master per active Remote Files connection.
- Reuse of that connection by folder listings, refreshes, image and Markdown
  preview retrieval, and downloads.
- Immediate navigation feedback, cancellable pending navigation, bounded
  directory caching, and background revalidation.
- Deterministic process-lifecycle, cache, interaction, and latency coverage.
- Updated Remote Files, process-lifecycle, security, and verification system
  documentation after implementation.

### Excluded

- Search, indexing, recursive metadata discovery, mounting, upload, editing,
  rename, move, delete, or synchronization.
- A persistent on-disk cache or content cache for downloaded file bytes.
- Reuse of a user's unrelated control socket or a forwarding profile's managed
  master.
- Parsing an undocumented long-lived interactive `sftp>` prompt, implementing
  a new SFTP protocol client, or adding an SSH/SFTP dependency.
- Release, publication, notarization, or deployment.

## Work

### 1. Reuse one owned SSH connection

- Add a Remote Files session owner that follows `TunnelStore`'s proven
  master-argument, private-socket, PID-ownership, and cleanup pattern without
  extracting or sharing tunnel profile state.
- Start a foreground `/usr/bin/ssh` master with `-N`, `-T`, `-M`, a private
  control socket, `ControlPersist=no`, `ClearAllForwardings=yes`,
  `BatchMode=yes`, a bounded connect timeout, and keepalives. Preserve the
  active server's validated host, identity, port, jump-host, authentication,
  host-key, and other allowed connection arguments.
- Create the short control-socket path below a random app-owned `0700`
  temporary directory, enforce the platform's Unix-socket path limit, and do
  not discover or attach to a control socket from OpenSSH config.
- Wait for the owned master to become ready before starting the first SFTP
  operation. Pass its exact control path and `ControlMaster=no` to each batch
  `/usr/bin/sftp` child so the healthy path opens only a new SSH channel, not a
  new network connection.
- Build master arguments from the same `SSHArgumentPolicy`-validated values as
  SFTP operations, using SSH-native `-p` and `-l` handling instead of SFTP's
  `-P` and `User=` translation.
- Keep listings, previews, and downloads as separately cancellable SFTP
  subprocesses with their existing output caps, parsing, staging, cleanup, and
  error normalization. Cancelling one child must not terminate the master.
- Serialize session startup so concurrent initial work cannot create duplicate
  masters for the same Remote Files window and connection identity.
- If the master dies, fail the affected operation through the existing
  nonblocking error and retry affordance, remove its stale socket, and start a
  new master only on the next explicit user action. Do not create a background
  reconnect loop or automatically retry a download.
- Add an explicit session shutdown hook. Invoke it on server change, return to
  the launcher, window close, and app quit; stop and reap every owned process,
  remove the socket and temporary directory, clear cached state, and prevent
  delayed callbacks from reviving the session.

### 2. Make navigation react immediately

- Add a session-only LRU cache keyed by the exact connection identity and
  normalized absolute path. Retain at most 20,000 aggregate entries by
  evicting whole least-recently-used snapshots; clear it when the connection
  changes or the window closes.
- On folder activation, update the presented target path immediately. Show a
  cached snapshot in the same event turn when available and revalidate it in
  place without replacing its rows with a blocking loading screen.
- On a cache miss, show a content-local **Opening folder…** state while keeping
  Back responsive and disabling Refresh and row actions. Back cancels the
  pending open and restores the prior folder and selection.
- Treat explicit Refresh as a cache-bypassing request. A failed background
  revalidation keeps the cached rows and reports a nonblocking error; a failed
  uncached open restores the prior folder and its navigation history.
- Coalesce duplicate requests for the same connection and path. Preserve the
  existing generation checks so late listing or revalidation results cannot
  replace a newer navigation result.
- Preserve mouse, Return, Command-Down, Command-Left-Bracket, Escape, and
  Command-R behavior, including selection restoration when returning to a
  parent folder.

### 3. Measure and verify the improvement

- Add injectable process/session seams so master reuse, readiness, early exit,
  cancellation, eviction, revalidation, and cleanup are deterministic in unit
  tests.
- Record before-and-after nested-navigation timings against a real
  high-latency SSH server as completion evidence. Keep environment-dependent
  wall-clock values out of automated pass/fail gates.
- Exercise nested navigation, Back, refresh, image preview, Markdown preview,
  file download, cancellation, connection loss, and window close against a
  real SSH server.
- Inspect the loading, cached-refresh, failure, and rapid-navigation states in
  light and dark appearance with mouse and keyboard input.

## Acceptance

- Opening an initial folder, five uncached nested folders, an image preview,
  and a Markdown preview through one server launches exactly one healthy
  Remote Files SSH master; every SFTP child uses its private control socket.
- After the first open, a healthy uncached folder navigation performs no new
  SSH key exchange or authentication. Recorded live before-and-after evidence
  shows the warm path no longer pays the connection and authentication phase.
- Cached Back and revisit navigation publish their rows synchronously in the
  same main-actor turn, then revalidate without blanking those rows.
- A folder click or keyboard activation changes the presented target
  immediately. Back remains usable during a cache miss, cancels that request,
  and restores the exact prior folder state.
- Duplicate path requests coalesce, and explicit user navigation supersedes
  an older revalidation.
- Refresh obtains a new listing, cache revalidation never blanks valid cached
  rows, and stale asynchronous results never overwrite the latest path.
- Cache tests prove the 20,000-entry limit, whole-snapshot LRU eviction,
  exact-connection isolation, and complete invalidation at session end.
- Cancelling a listing, preview, or transfer reaps only its SFTP child and
  leaves the healthy master reusable. Master loss causes no background
  reconnect or automatic transfer retry.
- Server change, launcher return, window close, and app quit leave no owned SSH
  or SFTP process, control socket, cache entry, preview file, or partial
  download behind.
- Existing path validation, SSH argument policy, batch quoting, output and
  entry caps, private permissions, error normalization, preview limits,
  download staging, and cancellation guarantees remain intact. Host-key
  verification occurs when the master is established rather than once per
  multiplexed child.
- Remote Files remains independent of forwarding-profile runtime state and
  does not reuse or alter user-managed SSH multiplexing.
- `swift test -Xswiftc -warnings-as-errors`, the Release build,
  `git diff --check`, visual review, and live-SSH verification pass.
- The affected system specs describe the implemented connection reuse, cache,
  interaction, cleanup, and residual first-open latency before this task is
  marked Complete and archived.
- Task implementation does not publish or deploy without separate explicit
  approval.
