# Task 026 Verification

Date: 2026-07-29

Updated: 2026-07-30

Result: Complete.

## Automated checks

- `swift test -Xswiftc -warnings-as-errors` passed 201 tests with 14 expected
  opt-in tests skipped and no failures.
- The new transport coverage verifies one serialized private master across the
  initial folder, five nested folders, image and Markdown preview retrieval,
  and download; native master arguments; exact SFTP control-path arguments;
  `0700` socket-directory permissions and ownership; the final socket and
  OpenSSH temporary-bind path limits; the real macOS temporary-root shape; early exit;
  readiness timeout; master loss; explicit-action-only reconnect; immediate
  startup-waiter cancellation; child-only cancellation; and cleanup.
- The new navigation coverage verifies exact-connection cache isolation,
  whole-snapshot LRU eviction, the 20,000-unit default bound, empty-folder
  bounding, complete invalidation, synchronous cached Back, nonblanking failed
  revalidation, immediate pending paths, duplicate coalescing, cancellation
  restoration, revalidation supersession, launcher shutdown, and connection
  switching after a failed initial open.
- The unsigned arm64 Xcode Release app build passed. The RelayBar target
  compiled with complete strict concurrency and warnings as errors.
- `Packaging/Info.plist` passed `plutil -lint`.
- `git diff --check` passed.

## Visual evidence

`VisualSnapshotHarness/testCaptureTask026Snapshots` passed and produced six
780 × 520 point captures: uncached **Opening folder…**, cached background
refresh, and failed cached revalidation in Aqua and Dark Aqua.

- The pending target path appears immediately while Back remains enabled and
  Refresh and row actions are unavailable.
- Cached rows and the restored selection remain visible while the Refresh
  affordance shows progress.
- Revalidation failure appears in the nonblocking error strip with **Try
  Again** while cached rows remain visible.
- All six PNGs were inspected from
  `/tmp/RelayBarTask026Snapshots-20260729`; they are reproducible verification
  output, not repository assets.

## Mouse and keyboard evidence

The isolated Debug fixture was exercised through the macOS accessibility
surface without touching the installed RelayBar process:

- a folder row was selected with the mouse and opened with Return;
- Command-Left-Bracket returned to the cached parent with its row selection
  restored;
- a Markdown row was selected with the mouse and opened with Return;
- Escape returned from preview to the same selected row;
- Command-R refreshed the visible directory without blanking or disrupting its
  selection.

## Independent review

The requested read-only CLI implementation review approved the design with
minor follow-ups. Its substantive findings were addressed before the final
checks:

- master readiness now has a 120-second bounded ceiling suitable for
  high-latency and jump-host handshakes while retaining 50-millisecond
  happy-path detection;
- startup waiters are cancellation-aware and a regression test proves a
  cancelled waiter returns promptly without starting SFTP;
- readiness timeout and connection-switch cleanup received direct coverage;
- SFTP checks the owned socket immediately before child spawn.

After a live Unix-socket path failure, a second requested Claude Fable CLI
review confirmed the connection-reuse architecture and recommended the final
path design:

- retain one owned SSH master plus cancellable one-shot SFTP children;
- keep the user's private macOS temporary root instead of moving into the
  shared `/tmp` namespace;
- atomically create a short `RelayBar-SSH.XXXXXXXX` directory with
  `mkdtemp(3)`, use the socket name `s`, and remove the previous
  check/remove/create sequence;
- derive the maximum final path as Darwin's 104-byte `sun_path`, less the NUL
  terminator and OpenSSH's 17-byte temporary bind suffix;
- cover the exact 86-byte success boundary, 87-byte rejection, real macOS
  temporary-root shape, permissions, ownership, and cleanup.

## Live socket-path correction

The first notarized build exposed a production-only path-budget error.
RelayBar checked only the final `ControlPath`, but OpenSSH temporarily appended
`.XXXXXXXXXXXXXXXX` before binding it. The resulting path was 105 bytes and
could not fit Darwin's 104-byte `sockaddr_un.sun_path`.

The corrected implementation uses the short, suffix-aware design above.
Focused strict tests passed all eight session cases. A real
`SFTPRemoteFileService` run then listed `/` through its shared SSH master
against `spark-422e.local` in 5.61 seconds.

## Live SSH evidence

The corrected build was exercised against `spark-422e.local` through the
installed, notarized application and direct OpenSSH instrumentation:

- a cold direct SFTP listing of `/` took 5.58 seconds;
- one foreground Remote Files master was then established on its private,
  29-byte control path;
- five warm listings through that master took 0.15, 0.09, 0.08, 0.08, and
  0.08 seconds;
- a verbose warm SFTP trace contained multiplexed-session requests and no new
  key exchange, authentication, or public-key offer;
- six nested folders were listed through the same master, from
  `/home/linxy97/workspace` through
  `previews/entryway/coat-racks`;
- the live service retrieved a 6,651-byte Markdown preview, an 11,373-byte
  640 × 640 JPEG preview, and a separate 6,651-byte Markdown download;
- the installed UI opened the same live Markdown and image previews, restored
  the selected row after Escape, retained selection through Command-R, and
  restored the selected child folder after Command-Left-Bracket;
- closing the Remote Files window stopped the one app-owned SSH master and
  removed its private socket directory. No app-owned SFTP child remained.

The user's original live connection-loss report reproduced the Unix-socket
failure that led to the suffix-aware path correction. Master-loss,
child-cancellation, explicit-action-only reconnect, transfer non-retry, and
partial-file cleanup are additionally covered by deterministic process tests
because their timing is not safe to gate on a production SSH host.

All Task 026 acceptance criteria have current automated, visual, interaction,
or live-SSH evidence.

## Explicitly approved local deployment

After the implementation verification, the user separately approved
notarizing the current working tree and replacing the installed application.
This did not publish a release:

- Apple accepted notary submission
  `973bbf99-71e2-4345-bc82-d8ec121c6a0c`.
- The ticket was stapled and validated, and Gatekeeper reported
  `source=Notarized Developer ID`.
- The installed `/Applications/RelayBar.app` is version 1.3.0, build 5, signed
  by `Developer ID Application: Thought Tides LLC (39HYFR5Z65)`.
- The installed executable matches the accepted build and launched
  successfully.
- The replaced application is recoverable from
  `~/Library/Application Support/RelayBar/Deployment Backups/RelayBar-pre-task026-20260730.rollback`.
  The non-`.app` suffix prevents Launch Services from selecting the rollback
  copy instead of the installed application.
- The notarized ZIP SHA-256 is
  `84a49a938722ec685ecbef1a9aaed895c4c7052b955eb0cd60f23a174e902fe0`.

After the live socket-path failure was corrected, the user-approved local
deployment was repeated:

- Apple accepted corrected submission
  `40e6466e-6c41-4f24-9e2c-f6e8bd035f95`.
- The corrected ticket, Developer ID signature, and Gatekeeper assessment all
  pass on `/Applications/RelayBar.app`.
- The installed executable matches the accepted build with SHA-256
  `d80ece9b7fba091205f7ef67a123d9f1164ecfe4c14072a5a1323be0ff86492f`.
- The corrected notarized ZIP SHA-256 is
  `c7cb2744881d54788e9fe4f21695c5f029b8bd32f32172a2d76309a06711da7f`.
- The replaced first Task 026 build remains recoverable from
  `~/Library/Application Support/RelayBar/Deployment Backups/RelayBar-pre-socket-fix-20260730.rollback`.
- The corrected installed application launched successfully.

No commit, push, release publication, or external deployment was performed.
