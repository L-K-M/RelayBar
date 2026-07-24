# Task 001 — Remote Files Verification

Status: Complete

Accepted: 2026-07-24

## Automated evidence

- `swift test`: 106 tests executed, 2 skipped, and 0 failed. The opt-in live-forward and Remote Files tests were skipped because no live-test environment was supplied.
- `swift test --sanitize=address`: the same 106 tests executed with 2 opt-in tests skipped, 0 failed, and no Address Sanitizer findings.
- `swift test --sanitize=thread`: the same 106 tests executed with 2 opt-in tests skipped, 0 failed, and no Thread Sanitizer findings.
- The opt-in live Remote Files test separately passed against `spark-422e.local` and the populated path `/home/linxy97/workspace` with the non-empty assertion enabled.
- Coverage verifies absolute-path validation and length bounds, linear normalization of a 32 KiB trailing-slash path, exact-connection server deduplication without alias/argument over-merging, stable selection when a duplicate representative changes, saved-server label normalization, batch quoting, SSH-to-SFTP argument translation, blocked and control-bearing option rejection, preservation of actionable diagnostics, friendly missing-path/host-key/refused-connection errors, long-listing parsing, basename and absolute-direct-child listing formats, rejection of out-of-folder absolute entries, per-line/name/size bounds, spaces in names, folder-first ordering, symbolic-link handling, direct-process failure, bounded command output and previews, launcher/folder navigation state, failed-folder retry, Back selection restoration, root and nested Back locking during transfer cleanup, off-main ImageIO decoding, cancellation during preview decoding, private `0700` download staging, explicit failure/cancellation cleanup messaging, safe replacement, near-limit local destination names, retry destination reuse, hidden-file folder progress, and isolation from delayed progress callbacks belonging to an earlier transfer attempt.
- The Xcode Debug target builds with complete strict-concurrency checking, warnings treated as errors, and code signing disabled.
- `git diff --check` and `plutil -lint RelayBar.xcodeproj/project.pbxproj` pass.

## Design evidence

- The implemented hierarchy follows [`remote-files-concept-a.png`](../designs/media/001/remote-files-concept-a.png).
- The menu-bar popover keeps forwarding primary and adds one labeled Remote Files row.
- The launcher, browser, preview, and transfer states are separate and contain no search, sidebar, inspector, editor, or download history.
- The current local debug harness was reviewed in light and dark appearance. The launcher shows the SSH identity `spark-422e.local` instead of the generated forwarding endpoint `127.0.0.1:4321`.
- A native picker fixture matching the reported duplicate case collapsed three `spark-422e.local` forwarding presets into one `spark-422e.local` entry while retaining `linxy97@spark-422e` as a separate SSH identity.
- Launcher Return, list focus, arrow selection, Return to open a folder, Space to preview an image, Escape to close preview, nested navigation, retry after a missing path, and Back selection restoration all passed in the native window.
- The browser was reduced to its minimum supported size with a long path and long filename. Both truncate in the middle while preserving navigation, modified time, file size, and the selected-row download action.
- Empty-folder presentation, refresh without losing the selected row, nonblocking refresh failure, dismissal, and successful **Try Again** recovery passed in the native window.
- File and recursive-folder transfers were reviewed through active and completed states. Determinate and indeterminate progress, disabled Back during transfer, cancellation cleanup, retry, permission failure, and **Reveal in Finder** presentation remained compact and readable.
- The image preview fits the complete image, uses only Back/filename/Download chrome, and exposes an explicit accessibility label.
- The missing-path state remains in the launcher, preserves the entered path and server, and reports `The remote path wasn’t found.` instead of raw SFTP output. Local launcher fixtures also expose concise permission-denied, host-key-verification, and connection-loss messages.
- Accessibility inspection confirmed descriptive rows, current-path context, transfer progress values and actions, error recovery controls, and explicit `Empty folder` and transfer-state labels instead of misleading SF Symbol names.
- The user-supplied saved-server run reached `spark-422e.local` and returned a real missing-path result for `/workspace`. This proves saved connection reuse and failure propagation, but it does not replace a successful real-path walkthrough.
- A read-only batch-mode `pwd` returned `/home/linxy97`. Native live review then exposed an interoperability defect: this server returns absolute entry paths, which the original parser discarded as unsafe basenames and incorrectly presented as an empty folder. The parser now accepts only absolute direct children of the requested path and rejects out-of-folder entries.
- The corrected development build opened populated `/home/linxy97/workspace`, navigated through two nested folder levels, previewed a real Markdown file and image, completed a file download and recursive folder download, canceled a second recursive transfer with cleanup, and preserved Back selection. All downloads stayed in the DEBUG review presenter's private temporary directory.
- Opening `/root` through the same live server produced the native launcher error `Permission was denied for this server or path.` without exposing raw SFTP diagnostics.
- Reaching the same live server through an untrusted IPv6 identity produced `SSH could not verify this server's host key.` A closed local SSH endpoint produced `The server refused the connection.` RelayBar no longer adds SFTP quiet mode implicitly because it hid both actionable OpenSSH diagnostics behind a generic `Connection closed`.

## Security evidence

- `/usr/bin/sftp` is invoked directly with structured arguments and batch input; no shell is used.
- Existing `SSHArgumentPolicy` validation runs before an SFTP process starts, rejects empty/control-bearing option values, and blocks quoted or persisted newline-shaped configuration injection.
- Remote paths reject relative values, line breaks, and control characters; quotes and backslashes are escaped for SFTP batch input.
- Listings, captured output, diagnostics, and preview size are capped; command output and preview storage use private temporary directories; canceled/failed transfers remove partial content.
- Recursive transfers poll directory byte progress once per second, check cancellation during enumeration, and saturate safely if aggregate local sizes overflow.
