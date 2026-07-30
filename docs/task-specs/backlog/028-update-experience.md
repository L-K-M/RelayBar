# Task 028 — Update Experience

Status: Backlog

Created: 2026-07-30

Deferred: 2026-07-30

## Outcome

Let users discover a newer stable RelayBar release and follow a trustworthy,
low-friction update path without creating disproportionate release or key
management overhead.

## Delivery Boundary

- Reassess this work after the Homebrew cask ships and the practical needs of
  direct-download users are clearer.
- Prefer Homebrew-backed guidance and a manual notarized-download path while
  RelayBar primarily serves technical users.
- Do not invoke Homebrew from RelayBar or build a custom
  download-replace-relaunch installer.
- Treat Sparkle as an optional future installation engine, not an approved
  dependency or release commitment.

## Work

- Choose a stable, unauthenticated release authority for manual and scheduled
  update detection.
- Design a quiet native indication, manual check, release-notes link, and clear
  Homebrew and direct-download guidance.
- Keep automatic checks user-controlled and avoid installation-source guesses
  that cannot be made reliably.
- Define evidence that would justify native in-app installation before
  reconsidering Sparkle and its signing-key lifecycle.

## Acceptance

- A reactivated task spec selects the update mechanism from current evidence
  and defines its privacy, security, recovery, release, and Homebrew behavior.
- The chosen experience avoids repeated menu-bar interruption and never
  downloads, installs, or invokes Homebrew unless a later task explicitly
  authorizes a proven installation design.
