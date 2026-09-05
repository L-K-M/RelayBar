# Task 064 — Upstream Workspace Integration Verification

## Automated evidence

- Baseline PR head `bf06c31`: [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/33959097643)
  passed 370 tests, with 17 opt-in skips, and the unsigned Xcode Release build.
- Test-only head `317004a`: [regression run](https://github.com/L-K-M/RelayBar/actions/runs/33960592234)
  compiled successfully, then failed four new tests with 13 expected assertions:
  detached cleanup exceeded its watchdog without TERM/KILL; normal cleanup also
  exceeded its watchdog; cancelled publication returned `CancellationError`;
  swapping the source uploaded the replacement contents instead of the chosen
  payload. Test watchdogs stopped the hung fixtures. Existing tests passed.
- Fix head `84ddaf8`: [macOS CI](https://github.com/L-K-M/RelayBar/actions/runs/33961047896)
  passed 375 tests with 17 opt-in skips and zero failures, including every new
  regression. The unsigned Xcode Release build passed. Local task-registry,
  fixture-syntax, and whitespace checks passed.
- Two independent read-only reviews found no remaining blocking issue in the
  upload fixes. Live and visual acceptance remain pending below.

## Review scope

The integration retains strict extension parsing, bounded UTF-8 captures,
symbolic-link browsing, direct-file Back, initial-open cancellation, SSH config
Includes, download permissions, and network-change reconnection. It changes no
bundle identity, release version, update feed, or release workflow.

## Remaining acceptance

Live-server upload/publication/cleanup, integrated Aqua/Dark Aqua review,
keyboard focus, VoiceOver, replacement confirmation, and native Quit remain
unverified here. This environment is Linux without Swift or AppKit; CI skips
opt-in live and visual checks. Upstream's workspace verification also records
live SSH as pending. Task 064 remains active; no release or deployment occurred.
