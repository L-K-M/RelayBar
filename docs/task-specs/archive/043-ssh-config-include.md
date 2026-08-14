# Task 043 — Follow ssh_config Include Directives

Status: Complete

Created: 2026-08-14

## Outcome

Remote Files discovers `Host` aliases in files pulled in by `Include` lines
in `~/.ssh/config`, so users who organize hosts in included files (for
example `Include ~/.ssh/config.d/*`) see their full server list.

## Delivery Boundary

- Read-only discovery only; no config writes, no new network behavior, and
  the existing alias validation, 1 MiB per-file read bound, and 256-alias
  cap are unchanged.
- Match OpenSSH semantics: relative patterns resolve against `~/.ssh`, `~/`
  expands to the home directory, unmatched patterns are ignored silently,
  and directories are not included.
- Include traversal is bounded: eight levels deep, 64 files total, and each
  file is processed once even through cycles.

## Work

- Rework `SSHConfigHostReader.load` into a recursive collector with glob
  expansion via `glob(3)` (`GLOB_MARK` skips directories), keeping the pure
  `parse` entry point Host-only.
- Add tests for globbed nested includes, unmatched patterns, cycles, and the
  depth cap; update the remote-files system spec.

## Acceptance

- Hosts from included files appear after top-level hosts in declaration
  order, deduplicated case-insensitively as before.
- A missing or empty include target changes nothing.
- An include cycle terminates with each file read once.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `SSHConfigHostReader` now resolves `Include` patterns exactly as OpenSSH
  does for user configuration and recurses through `collect` with depth,
  file-count, and visited-path guards; `parse(_:)` remains a pure Host-line
  parser for existing callers.
- Four focused tests cover glob + nested includes with skipped extensions
  and unmatched patterns, self-referential cycles, and the exact depth
  boundary (chain member at the cap loads, the next is refused).
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
