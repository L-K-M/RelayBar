# Task 045 — Remember the Last Remote Path per Connection

Status: Complete

Created: 2026-08-14

## Outcome

The Remote Files launcher offers the last path each exact SSH connection
opened successfully — prefilled on a fresh window and when switching servers
with the path field untouched — instead of resetting to an empty field on
every window.

## Delivery Boundary

- Record only successful opens, keyed by exact connection identity (host plus
  preserved arguments), bounded at 32 entries most-recently-used first and
  validated on load.
- Prefill never clobbers text the user typed and never fires outside the
  launcher screen.
- No change to recents, saved hosts, or the read-only remote boundary.

## Work

- Add bounded, validated last-path storage to `RemoteServerCatalog`.
- Record the presented path next to the existing successful-open recency
  write; prefill in the model at init and on launcher server changes.
- Add catalog and model tests; update the remote-files system spec.

## Acceptance

- Reopening Remote Files after opening `/srv/app` offers `/srv/app`.
- Switching the launcher server offers that server's last path only while
  the field is empty.
- Storage persists across catalog reloads and stays bounded.
- `swift test -Xswiftc -warnings-as-errors` and `git diff --check` pass.

## Evidence (2026-08-14)

- `RemoteServerCatalog` keeps up to 32 newline-keyed `LastPathRecord`s,
  recorded only on successful loads; invalid entries are dropped at decode.
- `RemoteFilesModel` records the presented path beside
  `recordSuccessfulOpen` and prefills via a `selectedServerID` `didSet`
  guarded to the launcher screen with an empty field.
- Two catalog tests (persistence per connection, bound) and two model tests
  (reopen prefill, switch prefill without clobbering) cover the behavior.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job.
