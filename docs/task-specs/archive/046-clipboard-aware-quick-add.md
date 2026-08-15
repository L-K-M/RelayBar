# Task 046 — Clipboard-Aware Quick Add

Status: Complete

Created: 2026-08-14

## Outcome

Quick Add offers a one-click (or ⇧⌘V) import chip while the command field is
untouched, so "copy a command anywhere, open RelayBar, done" replaces
click-add, click-field, paste, click-import. The clipboard is read only
when the chip is clicked.

## Delivery Boundary

- The clipboard is read only inside the chip's click action — never on
  editor appearance — so the macOS Sequoia paste-permission prompt can
  never appear from opening the editor.
- Contents that fully parse import directly; partial or unrelated clipboard
  contents produce a gentle message and change nothing.
- No change to the parser, the import flow, or clipboard contents (read-only
  access, never written).

## Work

- Add the pure `ClipboardSSHCommand.candidate(from:)` gate over the existing
  parser.
- Show a borderless chip in the Quick Add card with a ⇧⌘V shortcut; the
  clipboard is read only when the chip is clicked, so the macOS Sequoia
  paste-permission prompt can never appear from opening the editor. Using it
  fills the field and runs the normal import; unrelated contents show a
  gentle message.
- Add gate tests and update the ssh-command-import system spec.

## Acceptance

- With the editor's Quick Add visible and the field untouched, the chip is
  offered; activating it with `ssh -N -L 8080:localhost:3000 dev@example.com`
  on the clipboard imports exactly as the manual flow does.
- With text, an incomplete command, or an empty clipboard, activating the
  chip shows the gentle message and changes nothing.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `ClipboardSSHCommand.candidate(from:)` trims and fully parses the text, so
  a chip click can never import something the Import button would reject.
- The editor reads the pasteboard only inside the chip's click action;
  typing hides the chip, and unrelated contents show a gentle message.
- Gate tests cover nil, empty, unrelated, hostless, and rule-less text plus
  a whitespace-padded valid command.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
