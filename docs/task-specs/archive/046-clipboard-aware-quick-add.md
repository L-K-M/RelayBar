# Task 046 — Clipboard-Aware Quick Add

Status: Complete

Created: 2026-08-14

## Outcome

When the pasteboard already holds a complete, importable SSH forwarding
command as the profile editor opens, Quick Add offers a one-click (or ⇧⌘V)
import chip, so "copy a command anywhere, open RelayBar, done" replaces
click-add, click-field, paste, click-import.

## Delivery Boundary

- The suggestion appears only for text that fully parses as a
  forwarding-only ssh command — partial or unrelated clipboard contents
  never surface.
- One read on editor appearance (a user action), one suggestion per editor
  session; typing or using the chip dismisses it.
- No change to the parser, the import flow, or clipboard contents (read-only
  access, never written).

## Work

- Add the pure `ClipboardSSHCommand.candidate(from:)` gate over the existing
  parser.
- Show a borderless chip in the Quick Add card with the command as its
  tooltip and a ⇧⌘V shortcut; using it fills the field and runs the normal
  import.
- Add gate tests and update the ssh-command-import system spec.

## Acceptance

- With `ssh -N -L 8080:localhost:3000 dev@example.com` on the clipboard, the
  new-profile editor shows the chip; activating it imports exactly as the
  manual flow does.
- With text, an incomplete command, or an empty clipboard, nothing appears.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `ClipboardSSHCommand.candidate(from:)` trims and fully parses the text, so
  the chip can never offer something the Import button would reject.
- The editor reads the pasteboard once in `onAppear` (itself a user action)
  and clears the suggestion on any edit to the command field.
- Gate tests cover nil, empty, unrelated, hostless, and rule-less text plus
  a whitespace-padded valid command.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
