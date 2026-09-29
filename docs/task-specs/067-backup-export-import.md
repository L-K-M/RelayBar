# Task 067 — Backup, Export, and Import

Status: In Progress

Created: 2026-09-29

## Outcome

Your forwarding profiles and saved Remote Files hosts can be backed up
automatically to a folder you choose, exported to a file, and imported
again on this Mac or another one.

## Delivery Boundary

- A backup carries forwarding profiles and standalone Remote Files hosts.
  Recent connections and locations, menu and window sizes, Launch at Login,
  and updater preferences stay out: they are history or device state.
- Automatic backups are off until you turn them on and choose a folder.
  After a change settles, RelayBar writes a timestamped backup only when the
  contents differ from the last one written, keeps the newest 30 automatic
  backups, and never deletes any other file. An empty profile and host list
  is never backed up. A missing folder is reported, never created.
- Export writes the same format to a file you pick.
- Import validates the whole file before anything changes, then asks:
  **Add Missing** adds profiles and hosts that are not saved yet and leaves
  everything saved unchanged; **Replace All** stops active tunnels and makes
  the saved profiles and hosts exactly the backup's. Nothing starts.
- Backup files are JSON, readable by a person, and restricted to their owner.

## Work

- Add the backup format, validation, file naming, retention, and copy in
  `RelayBarBackup.swift`, and `BackupModel` with its panel and data-source
  boundaries in `BackupModel.swift`.
- Add `TunnelStore.importProfiles(_:mode:)` and
  `RemoteServerCatalog.importSavedHosts(_:mode:)`, sharing the saved-host
  validation with the decoder.
- Add a **Backup** section to Settings.
- Add a backup module spec and update the application-shell,
  data-and-state, security-boundaries, and tunnel-management specs and the
  privacy policy.
- Add codec, naming, preview, store, catalog, model, and round-trip tests.

## Acceptance

- Turning on automatic backups asks for a folder, writes a backup there,
  and survives relaunch; cancelling the folder panel leaves them off.
- Editing a profile or adding a Remote Files host writes one new backup
  after the change settles; a change that leaves the contents equal writes
  none; the folder keeps at most 30 automatic backups and every other file.
- Export then import with Replace All into an empty install reproduces the
  profiles and hosts exactly.
- Add Missing never changes or stops a saved profile. Replace All stops
  active tunnels before replacing.
- A non-backup file, a newer format version, an invalid profile or host,
  and a file over 4 MiB are refused with a named reason and change nothing.
- `swift test -Xswiftc -warnings-as-errors`, the Release build, and
  `git diff --check` pass.
- Manual: the folder, export, and import panels open from the menu, the
  import confirmation shows the right counts, and the Backup section fits
  Settings in light and dark appearance.
