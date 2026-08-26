# Task 036 — Remote Files Workspace Design

Status: Complete

Created: 2026-08-20
Completed: 2026-08-24

## Outcome

Define and approve a modular redesign of Remote Files that reduces repeat
navigation to common remote folders, keeps recent folders and hosts available
in a persistent sidebar, and adds a clear upload entry point to the folder
detail pane.

## Delivery Boundary

### Included

- Document the workspace user flow, persistent recent-location behavior,
  add-path flow, upload safety contract, accessibility states, and verification
  expectations.
- Produce a visual mock covering the welcome, folder, add-path, upload, and
  preview states.
- Review the proposal with Claude Fable through the Claude Code CLI and resolve
  all blocking design findings.

### Excluded

- Product implementation, automated tests, live-SSH verification, release, or
  deployment. Implementation is tracked by Task 037.

## Work

- Audited the existing Remote Files launcher, browser, preview, download, SSH,
  persistence, and teardown behavior.
- Defined a single resizable split workspace with one contextual sidebar and a
  quiet no-connection welcome state.
- Defined exact recent-location persistence bounds and explicit activation
  semantics so focus traversal never initiates SSH.
- Defined the add-path sheet and failure-safe staged upload contract, including
  exact SFTP extension requirements and truthful race and cleanup behavior.
- Produced the approved mock and incorporated two rounds of Fable review.

## Acceptance

- The mock presents the approved workspace hierarchy and principal interaction
  states.
- The written design has a concrete implementation and verification boundary.
- Fable reports no unresolved blocker or P1 issue.
- The maintainer approves the mock and directs implementation into Task 037.
- No implementation behavior is presented as shipped current state.

## Evidence

- [Approved Remote Files workspace mock](../../designs/media/036/remote-files-workspace.png)
- Maintainer approval recorded on 2026-08-24: the mock looks good and the
  implementation remains scoped to Task 037.
- Task 037 preserves the approved implementation and acceptance contract.
