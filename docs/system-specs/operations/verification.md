# Verification

## Required checks

- Run `swift test` for parsing, safety, retry, cancellation, browser URL behavior, Remote Files path/argument handling, listing parsing, navigation state, Markdown compatibility, link policy, and renderer limits.
- Build the Xcode app target with complete Swift strict-concurrency checking and warnings treated as errors.
- Run `git diff --check` before committing.

## Optional live check

Set `RELAYBAR_LIVE_TEST=1` and `RELAYBAR_LIVE_SSH_HOST` to test a real SSH forward and HTTP response on local port 3000.

Set `RELAYBAR_REMOTE_FILES_LIVE_TEST=1`, `RELAYBAR_LIVE_SSH_HOST`, and `RELAYBAR_LIVE_REMOTE_PATH` to run the opt-in Remote Files listing test against a real saved-server target. Add `RELAYBAR_LIVE_REMOTE_EXPECT_NONEMPTY=1` when the configured path is known to contain entries so a false empty-folder result fails the test.

Remote Files changes should additionally exercise that server and absolute path manually for nested navigation, refresh, file download, recursive folder download, cancellation, image preview, and representative failures.

Before a live server is available, use the DEBUG-only Remote Files fixture to review light and dark appearance, minimum-window truncation, empty folders, long names, image and Markdown previews, refresh recovery, initial connection errors, and active, completed, failed, and canceled transfers. Fixture downloads must remain inside their private temporary directory and must not open Finder.

For a native live-transport review without changing the user's saved tunnels, start a DEBUG build with `--remote-files-live-preview <ssh-host>`. This route uses the real SFTP service while keeping review downloads inside the same private temporary directory and suppressing Finder launch.

Markdown changes should exercise a local fixture in light and dark appearance for GFM, properties, callouts, code highlighting/copy, math, footnotes, blocked images/embeds, wiki links, inert tags, Mermaid source, raw HTML, keyboard return, and accessibility reading order.

Changes to bundled renderer resources should build the Xcode app in Debug and Release, verify that Highlighter retains only its formatter and the `github`/`github-dark` themes, verify that SwiftMath retains only Latin Modern metrics/font and licenses, record the Release app and executable sizes, match the stripped executable to its dSYM UUID, and exercise the affected renderer in the native fixture.

Release changes should additionally verify the code signature and notarized app with the scripts in [Build and release](build-and-release.md).
