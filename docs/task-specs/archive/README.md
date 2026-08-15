# Accepted Task Specifications

Move a task spec into this directory only after its acceptance criteria pass and its status is `Complete`.

A number missing from the list below is not a gap to be filled, and this list is not by itself proof that a number is free — it covers accepted work only. Before claiming one, check the filenames in this directory, the active specs in [`../`](../README.md), and the spec filenames on every open pull request. Read the filenames rather than this list — the list has drifted from them before. The last check is the one that bites: a branch can hold a number for days before it merges, so two changes can each pick the "next free" value and only collide at merge time.

- [Task 001 — Remote Files](001-remote-files.md)
- [Task 002 — Read-only Markdown](002-read-only-markdown.md)
- [Task 003 — Flexible SSH Forwarding Profiles](003-flexible-ssh-forwarding.md)
- [Task 004 — Group Saved Forwards by Tag](004-group-saved-forwards-by-tag.md)

Tasks 005 through 019 came from one review pass over the app sources for reliability, performance, and conciseness. They share [one verification report](../../verification/005-019-audit-remediation.md).

- [Task 005 — Reject Remote Paths That sftp Would Glob](005-reject-glob-metacharacter-paths.md) — **withdrawn**, the finding was incorrect and the change was reverted
- [Task 006 — Clear Control Pipe Handlers Before Draining](006-clear-pipe-handlers-before-draining.md)
- [Task 007 — Key SSH Control State by Launch](007-key-control-state-by-launch.md)
- [Task 008 — Remove the PID-Based Force-Kill Race](008-remove-pid-force-kill-race.md)
- [Task 009 — Build Tunnel Grouping Once Per Render](009-build-grouping-once-per-render.md)
- [Task 010 — Compile the PermitRemoteOpen Expression Once](010-compile-permitremoteopen-expression-once.md)
- [Task 011 — Bound Directory Download Progress Polling](011-bound-directory-progress-polling.md)
- [Task 012 — Cheapen Syntax Highlight Cache Lookups](012-cheapen-highlight-cache-lookups.md) — **withdrawn**, measured 28-179x slower than what it replaced
- [Task 013 — Hoist Cancellation Checks Out of Leaf Scanners](013-hoist-cancellation-checks.md) — **withdrawn**, the removed cost measured under 1% of a render
- [Task 014 — Remove Formatter and Filesystem Work From View Bodies](014-remove-work-from-view-bodies.md)
- [Task 015 — Table-Driven sftp Error Messages](015-table-driven-sftp-messages.md)
- [Task 016 — Deduplicate Control Output Buffering](016-deduplicate-control-buffering.md)
- [Task 017 — Name the Master Error Buffer Limit](017-name-master-error-buffer-limit.md)
- [Task 018 — Remove Dead Compatibility Accessors](018-remove-dead-compatibility-accessors.md)
- [Task 019 — Count Running Phases Without an Intermediate Array](019-count-running-phases-without-array.md)

- [Task 020 — Refresh GitHub Pages Landing Page](020-refresh-github-pages-landing-page.md)
- [Task 021 — Fix Profile Editor and Add Remote Hosts](021-fix-profile-editor-and-add-remote-hosts.md)
- [Task 022 — Launch at Login](022-launch-at-login.md)
- [Task 023 — Homebrew Cask](023-homebrew-cask.md)
- [Task 024 — Group Lifecycle Actions](024-group-lifecycle-actions.md)
- [Task 025 — Fix Rule Type Label Wrapping](025-fix-rule-type-label-wrapping.md)
- [Task 026 — Make Remote Files Navigation Responsive](026-responsive-remote-files-navigation.md)
- [Task 027 — Preview Sidebar and Polish](027-preview-sidebar-and-polish.md)
- [Task 028 — Secure Self-Updates](028-secure-self-updates.md)
- [Task 029 — Formal Notarized 1.3.0 Release](029-formal-notarized-1.3.0-release.md)
- [Task 030 — Show Version and Project Links](030-version-and-project-links.md)
- [Task 031 — Fix Edit Profile Insets](031-fix-edit-profile-insets.md)
- [Task 033 — Private Update Rehearsal Correctness](033-private-update-rehearsal-correctness.md)
- [Task 035 — Add GLM 5.3 PR Review](035-add-glm-5-3-pr-review.md)
- [Task 036 — Status-Item Click Dismisses the Popover](036-status-item-click-dismisses-popover.md)
- [Task 037 — Atomic Forwarding Control Paths](037-atomic-forwarding-control-paths.md)
- [Task 038 — Back From a Direct File Opens the Containing Folder](038-back-from-direct-file-opens-folder.md)
- [Task 039 — Duplicate Profile](039-duplicate-profile.md)
- [Task 040 — Live Retry Countdown](040-live-retry-countdown.md)
- [Task 041 — Quit Confirmation With Active Tunnels](041-quit-confirmation-active-tunnels.md)
- [Task 042 — Copy Profile as SSH Command](042-copy-ssh-command.md)
- [Task 043 — Follow ssh_config Include Directives](043-ssh-config-include.md)
- [Task 044 — Lock Down Finished Downloads](044-download-final-permissions.md)
- [Task 045 — Remember the Last Remote Path per Connection](045-last-remote-path-per-connection.md)
- [Task 046 — Clipboard-Aware Quick Add](046-clipboard-aware-quick-add.md)
- [Task 047 — Force Safe SSH Master Invariants](047-force-safe-ssh-master-invariants.md)
- [Task 048 — Popover Visual Polish: Hover Buttons, Consistent Menu, Error Tooltips](048-popover-visual-polish.md)
- [Task 049 — Confirm Profile Deletion](049-confirm-profile-deletion.md)
- [Task 050 — Navigate Symbolic Links in Remote Files](050-symlink-navigation.md)
- [Task 051 — Cancel Initial Remote Files Open](051-cancel-initial-remote-open.md)
- [Task 052 — Status Item Failure Attention](052-status-item-failure-attention.md)
- [Task 054 — Align Update UI and Documentation](054-update-documentation-truth.md)
- [Task 055 — Reject Invalid SFTP UTF-8](055-reject-invalid-sftp-utf8.md)
- [Task 057 — Stable Form Accessibility Labels](057-stable-form-accessibility-labels.md)
- [Task 058 — The Editor Explains Why Save Is Disabled](058-editor-validation-reasons.md)
- [Task 059 — Notify When a Profile Stops Retrying](059-retry-exhaustion-notification.md)
