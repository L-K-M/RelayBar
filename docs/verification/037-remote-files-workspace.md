# Task 037 — Remote Files Workspace Verification

Verified: 2026-08-24

Result: Automated, visual, documentation, and fake-process safety evidence
passes. Required live-SSH workflow evidence is pending because the configured
target timed out before authentication; Task 037 remains active.

## Automated evidence

- `swift test -j 1 --no-parallel -Xswiftc -warnings-as-errors` passed 269
  tests with 16 expected opt-in tests skipped and no failures.
- Catalog and model coverage verifies success-only path history, normalized
  connection-and-path deduplication, ordering, the 16-location and eight-host
  bounds, direct-file parent recording, isolated removal and clearing, empty
  migration, no connection on window open, one-click activation, failed-path
  retry/removal, root marking, Back-to-welcome teardown, preview cancellation,
  expanded global/nested deduplication, wrong-host failure isolation, transfer
  gates, upload consent/retry, cancellation, and deferred shutdown completion.
- SFTP process coverage verifies exact extension parsing, one probe per owned
  master, reprobe after master replacement, new-name hard-link publication,
  approved POSIX rename, absent extensions, directory and symbolic-link refusal,
  pre-publish and hard-link collision races, session loss, cancel during staging,
  cancel after confirmed publication, exact cleanup, bounded cleanup retry,
  published and unpublished cleanup uncertainty, and removal of debug
  diagnostics from user-visible errors.
- Sidebar focus-navigation coverage proves Up/Down changes only focus and stays
  within the visible order. The window installs a separate Return monitor for
  explicit focused-row activation and prevents the file-list monitor from
  handling Return while sidebar focus is active.
- The warnings-as-errors unsigned Xcode Release build and the repository's
  Developer-ID signing workflow passed for the RelayBar 1.5.0 build 9 universal
  candidate. Every nested Sparkle boundary passes strict signature validation,
  both architectures retain the macOS 13 minimum, and the executable/dSYM UUIDs
  match. `plutil -lint RelayBar.xcodeproj/project.pbxproj Packaging/Info.plist`
  and `git diff --check` also passed.

## Visual evidence

`VisualSnapshotHarness/testCaptureTask037RemoteFilesWorkspaceSnapshots` passed
and produced 24 reproducible PNGs in Aqua and Dark Aqua. The inspected states
cover:

- welcome with expanded host paths and no active network connection;
- populated folder, dedicated long-path truncation, 760 × 440 minimum window,
  and a simulated 125% text/interface scale (macOS does not apply Dynamic Type
  categories to these controls in the offscreen harness);
- explicit keyboard focus, single-sidebar Markdown preview, Add Path
  validation, and empty history;
- upload staging progress, post-conflict retry, and stale-path Retry/Remove.

The captures are temporary verification output rather than repository assets.
The replacement-consent alert is an AppKit modal and is verified in source and
presenter coverage instead of the offscreen SwiftUI harness. Its text names the
remote item and discloses that another client can change the name during the
final check.

The maintainer installed the Developer-ID-signed universal application in
`/Applications`, opened the redesigned Remote Files workspace, and reported on
2026-08-24 that the overall installed experience looks good. The accepted beta
identity is RelayBar 1.5.0 build 9, tagged `v1.5.0-beta.1` when beta publication
evidence is complete.

## Safety and lifecycle evidence

- A failed host switch clears the former host's listing and folder capability
  before the new load starts. The regression then proves Refresh, Upload, and
  row actions cannot run the prior path through the new connection.
- Location activation cancels and generation-retires pending preview work,
  removes its private temporary directory, and prevents stale preview errors
  from publishing into the new root.
- Upload cancellation before publication returns only after exact staging
  cleanup is confirmed; cancellation after hard-link publication is confirmed
  as success. Unconfirmed cleanup is a distinct error.
- Window close retains a retiring model until upload cleanup ends and the owned
  master shuts down. App termination uses `.terminateLater` and replies only
  after every retiring Remote Files model completes.
- Recent history persists only normalized paths, exact connection identity,
  stable IDs, and bounded display metadata. Privacy, security, data/state,
  application-shell, process-lifecycle, operations, design, and README records
  describe the new behavior.

## Fable review

The first final read-only Claude Fable CLI review on 2026-08-24 withheld
approval for one wrong-host blocker and P1 findings involving late upload
cancellation, preview retirement, revalidation activation, application quit,
Return activation, expanded-history duplication, and outdated documentation.
Each finding received a code or documentation change plus focused regression
coverage. The second review confirmed those remediations but found one remaining
P1: approved upload-replacement consent and a failed download retry could follow
navigation to another host or folder. Upload and download presentations now
store their originating connection and directory, finished cards clear on
navigation, retry validates both values, and cross-host upload/download
regressions pass. The final approval-only review found no remaining Blocker or
P1 issue within the approved Task 037 boundary. Fable identified live-server
coverage, native replacement-consent presentation, and true Dynamic Type
rendering as manual limitations rather than implementation findings.

## Live SSH limitation

The previously configured SSH target was exercised read-only with `/` as the
absolute path. Its owned master reached the ten-second connection timeout before
authentication, so no SFTP child, upload, or remote mutation occurred. Because
no currently reachable isolated writable target was available, the required
real-server open/revisit/preview/download/upload/cancel/retry/history/close flow
and actual server extension advertisements remain unverified. Fake-process
tests prove both advertised-support and failure-closed paths, but do not replace
the required live evidence.

The initial implementation-verification pass performed no commit, push,
release, notarization, publication, or deployment. The maintainer subsequently
authorized committing and pushing the accepted implementation and preparing
RelayBar 1.5.0 Beta 1.
