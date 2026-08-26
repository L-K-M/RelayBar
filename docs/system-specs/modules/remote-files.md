# Remote Files

Remote Files opens an exact folder or supported preview file on an SSH server
without adding search, indexing, mounting, or editing.

## Entry and window

- A labeled **Remote Files…** row appears below the tunnel list.
- The row opens or focuses one 920 × 600 point resizable split workspace with a
  760 × 440 minimum. Its native leading sidebar is 210–360 points wide and can
  be hidden or restored with Control-Command-S.
- Opening the window performs no SSH operation. A pointer or accessibility
  activation, or Return on a focused location, is the explicit connection
  action; focus and arrow-key traversal never connect.
- **Recent Folders** shows at most six of the 16 locally persisted successful
  host-and-normalized-path pairs before **Show All**. **Recent Hosts** retains
  at most eight connections and can disclose up to three additional,
  nonduplicated paths before its own overflow action.
- **Add Path…** opens a focused sheet containing the complete host picker, one
  validated absolute path, and **Add Host…**. A failed open leaves the entered
  host and path available for retry. A forwarding profile is not required.
- The server picker combines successfully opened recent connections, standalone hosts saved in RelayBar, forwarding-profile connections, and concrete aliases from `~/.ssh/config`, in that priority order.
- Equivalent entries with the exact same SSH host and SSH arguments collapse into one SSH-host entry. Group tags and forwarding-rule differences do not split equivalent connections. Different host aliases or SSH arguments remain separate because they may select different credentials, ports, or routes.
- A single Quick Add tunnel whose generated name matches its forwarded destination is labelled by its SSH host in the server picker. An intentional custom name remains visible with the SSH host for context when that SSH connection is not duplicated.
- **Add SSH Host** accepts an optional local display name and a validated `user@server`-style SSH target. It saves Remote Files metadata only: it does not create a forwarding profile, add a forwarding rule, start SSH, or edit OpenSSH config.
- A standalone saved host can be removed after confirmation. Removal also drops
  its matching recent host and path records but does not change forwarding
  profiles or OpenSSH config.
- Only successful folder or file opens are promoted. Direct-file opens record
  the parent folder. Failed, cancelled, and superseded opens do not change
  recency. One location or all path history can be removed without removing
  unrelated hosts.
- OpenSSH config discovery reads at most 1 MiB from `~/.ssh/config`, exposes at most 256 concrete `Host` aliases, and ignores wildcard, character-pattern, and negated aliases. Config aliases remain read-only and are not copied into RelayBar storage.
- Missing-path output from SFTP is normalized to a short user-facing error while preserving the entered path and server for retry.
- When an entered path identifies a supported image or Markdown file, RelayBar
  opens the existing bounded preview with that exact file selected. Back returns
  through a single-file browser context to the welcome workspace. Another regular file
  is shown selected in that context without starting a download automatically.

## Folder browser

- The top bar contains **Back**, the exact current path, **Refresh**, and
  **Upload…**.
- The list shows supported folders, regular files, and symbolic links with modified text and size.
- Folders sort before other items; each group uses localized name ordering.
- Activating a folder presents its target path immediately. An uncached folder shows a content-local **Opening folder…** state; rows and Refresh are disabled, while Back remains available to cancel the open and restore the exact prior folder and selection.
- Successful listings enter a session-only LRU cache keyed by exact SSH connection identity and normalized absolute path. The cache retains at most 20,000 aggregate entry units, charges an empty snapshot one unit, and evicts whole least-recently-used snapshots.
- Cached Back and revisit navigation publish rows synchronously, then revalidate them in place. Revalidation keeps the rows visible, preserves selection when possible, and reports failure through the existing nonblocking error and retry affordance.
- Explicit Refresh bypasses the cache. Duplicate loads for the same presented path coalesce, and generation checks prevent a superseded listing or revalidation from changing the current folder.
- Back follows navigation history, reselects the folder that was left, and
  returns to the quiet welcome detail from the initial folder. That transition
  clears the active root, snapshots, preview content, and SSH session.
- Supported images and Markdown documents open a split preview workspace. Other files begin destination selection for download.
- Search, filters, indexing, workspace discovery, rename, move, delete, folder
  or multi-file upload, synchronization, and remote editing are absent.

## Uploads

- **Upload…** accepts one local regular non-symbolic-link file only while a
  folder is open and no upload or download is active. Progress is deliberately
  indeterminate and names the staging, publishing, or cleanup phase.
- RelayBar revalidates the target name. An observed directory or symbolic link
  is refused. An observed regular file requires a confirmation that identifies
  the bounded race with another remote client.
- Once per owned SSH session, an app-controlled `sftp -vv` probe recognizes
  only exact `hardlink@openssh.com` and `posix-rename@openssh.com`
  advertisements. Debug diagnostics are never surfaced or persisted.
- Bytes first reach a same-directory hidden
  `.relaybar-upload-<UUID>.partial` name. A new target requires the hard-link
  extension for no-overwrite publication, followed by removal of the staging
  name. An approved replacement requires POSIX rename for atomic replacement.
  Missing extensions, target-type changes, connection-master replacement, and
  hard-link collisions fail closed.
- Cancellation before publication removes the exact staging name. Cancellation
  after confirmed publication reports completion. Cleanup uses no shell,
  wildcard, recursive delete, or guessed path; an unconfirmed removal is
  reported explicitly. Closing the window retains the cleanup owner until the
  attempt and SSH-master shutdown finish, and application termination waits for
  that retirement.
- A successful upload refreshes the current rows without first blanking them.

## Downloads

- Regular files use the macOS save panel.
- Folders use a directory chooser and recursive SFTP retrieval.
- One transfer runs at a time.
- A temporary strip reports progress, supports cancellation, and offers **Reveal in Finder** after completion.
- Back navigation is disabled in every browser folder while a transfer is active or still cleaning up.
- Transfer progress and state icons expose explicit accessibility descriptions rather than relying on system-symbol names.
- Downloads use a hidden, fixed-length UUID staging directory beside the destination. The directory is created with mode `0700` before SFTP writes its payload, and its bounded name avoids exceeding local filesystem limits when the chosen destination name is long. Existing content is replaced only after the new transfer succeeds.
- Cancellation and failure remove the complete staging directory and leave an existing destination unchanged.
- Cancellation and failure messages explicitly state that temporary data was removed and existing files were unchanged.
- Transfer progress is scoped to its originating attempt; a delayed callback from a failed or cancelled attempt cannot update a retry.
- Completed and failed upload or download cards remain bound to the connection and normalized directory where the transfer began. Beginning navigation clears those cards, and retry refuses to run if the active connection or directory no longer matches that origin.
- Single-file progress polls every 250 ms. Recursive progress re-walks the partial tree, so its interval scales with the entry count from 1 second up to a bounded 8 seconds. The completion report is exact regardless of interval.
- A cancelled SFTP operation receives `SIGTERM` once. After two seconds, RelayBar reaps the child first and sends `SIGKILL` at most once only while it still owns that child. Reaping and signal delivery are serialized, so the PID cannot be recycled between the decision and the signal.

## Preview workspace

- Preview reuses the workspace's one draggable leading sidebar. **In This
  Folder** appears above Recent Folders and Recent Hosts and contains only
  previewable image and Markdown siblings from the current in-memory folder
  snapshot; opening preview performs no additional listing, recursive
  discovery, search, or eager sibling download.
- The active file stays selected. Clicking a sibling or pressing Left or Right starts that preview through the active server and SSH master. Superseded retrieval and decoding work is cancelled, generation-guarded, and cleaned before stale content can publish.
- The leading sidebar control hides or restores the pane with Control-Command-S.
  While sidebar focus is active, Up/Down moves focus, Left/Right controls host
  disclosure, and Return explicitly activates. Left/Right switches preview
  siblings only from the detail or while the sidebar is hidden. The active
  sibling owns selection and the workspace root retains a separate marker and
  accessibility description.
- **All Files**, Escape, and Command-Left-Bracket return to the complete browser with the active preview row selected. Download remains the only trailing toolbar action.
- Loading, error, retry, and transfer feedback stays in the detail pane so the sibling list remains stable.

## Image preview

- PNG, JPEG, GIF, HEIC/HEIF, TIFF, and BMP files are previewable.
- Preview retrieval is limited to 100 MiB.
- Bounded native ImageIO thumbnail decoding runs off the main actor from private temporary storage; only the completed immutable image is published back to the UI.
- Leaving the preview or closing the window removes preview content, including when cancellation happens after retrieval but during decoding.
- The detail uses an adaptive quiet canvas, keeps intrinsic aspect ratio, and never enlarges an image beyond its decoded dimensions.
- Preview has no thumbnails, metadata inspector, markup, or editing behavior.

Empty folders show a single focused empty state with an explicit accessibility description.

## Markdown preview

- `.md`, `.markdown`, `.mdown`, and `.mkd` files use the same split preview workspace.
- Preview retrieval is limited to 2 MiB and accepts UTF-8 without NULs.
- The reader is selectable and read-only; it does not fetch document images, resolve remote embeds, execute HTML or Mermaid, or write remote content.
- Detailed behavior and limits live in [Markdown preview](markdown-preview.md).

## Transport and lifecycle

- RelayBar starts one foreground `/usr/bin/ssh` multiplexing master for the active Remote Files connection, then invokes `/usr/bin/sftp` directly for each listing, preview, download, upload, publication, and cleanup operation. It never invokes a shell.
- The master uses `-N`, `-T`, `-M`, `ControlPersist=no`, `ClearAllForwardings=yes`, `BatchMode=yes`, a 10-second connect timeout, forward-failure exit, and server keepalives. Its input and output are discarded and its last 16 KiB of standard error is retained for a normalized failure.
- A one-character control socket lives below a short app-owned directory that `mkdtemp(3)` creates atomically with `0700` permissions under the user's private macOS temporary directory. Its UTF-8 path budget reserves the terminating NUL and OpenSSH's 17-byte temporary mux-listener suffix instead of checking only the final socket name. SFTP children receive that exact `ControlPath` with `ControlMaster=no`; RelayBar neither discovers nor attaches to a user-managed socket or a forwarding profile's master.
- Concurrent first operations serialize behind one master startup. Readiness is detected at 50-millisecond intervals with a bounded 120-second ceiling for high-latency and jump-host handshakes. Cancelling a startup waiter resumes it immediately without stopping the master, and cancelling an SFTP child leaves the healthy master running. An unexpected master exit cleans its socket and does not reconnect in the background; the next explicit operation creates a new master.
- The session and directory cache end on connection change, welcome return,
  window close, or app quit. Delayed callbacks cannot revive the retired
  session. A failed cross-host root open clears the former host's listing before
  it can expose any operation against the new connection.
- Remote and local batch paths are limited to 32 KiB of UTF-8 before quoting.
- Batch paths are quoted with `\` and `"` escaped. sftp's own quoting suppresses `glob(3)` expansion, so `*`, `?`, and `[` in a remote path resolve literally and need no further escaping. Verified against OpenSSH 10.2 with `star*dir`, `report[2026]`, `bra[ck]et.md`, and `draft?.md`, all of which list and open correctly.
- Captured standard output is capped at 32 MiB and standard error at 1 MiB.
- The batch-input pipe suppresses `SIGPIPE`; if the child exits before input is written, RelayBar handles the write failure instead of terminating.
- Close-by-default spawning explicitly preserves the batch reader as child standard input, including when that reader already occupies descriptor zero.
- Parsed listing lines are limited to 32 KiB, entry names to 4 KiB, entry sizes must be nonnegative, and supported entries remain capped at 10,000.
- Listing rows may contain either basenames or absolute paths. An exact regular-
  file row may resolve the launcher path itself. Folder rows accept an absolute
  entry only when it is a direct child of the requested folder, then reduce it
  to its basename; out-of-folder absolute entries fail closed.
- RelayBar does not add SFTP quiet mode implicitly, so bounded diagnostics retain actionable host-key, resolution, timeout, refusal, and connection-loss details for normalization. A user-saved `-q` option is still preserved.
- The master receives validated SSH-native connection arguments. SFTP children receive the same validated connection behavior with SFTP-specific translation, including SSH `-p` to SFTP `-P` and SSH `-l` to `User=`.
- The user's normal OpenSSH config, identities, agent, jump host, and host-key behavior remain in effect.
- Browsing is independent of the local-forward process state.
- Closing the Remote Files window or quitting RelayBar cancels listing, preview, and transfer work, stops the owned master, clears the cache, and removes owned temporary state.

See [Security boundaries](../shared/security-boundaries.md).
