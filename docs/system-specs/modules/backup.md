# Backup and Restore

The Settings **Backup** section backs up saved work automatically to a folder
the user chooses, exports it to a file, and imports it again.

## Contents

- A backup carries forwarding profiles and standalone Remote Files hosts.
  Recent connections and locations, the menu size, Launch at Login, updater
  preferences, and runtime state are not included.
- The file is one pretty-printed JSON object with sorted keys: `format`
  (`com.relaybarscion.backup`), `version` (currently `1`), `createdAt`
  (ISO 8601), `profiles` (the same records as `savedTunnels.v2`), and
  `remoteFilesHosts` (`id`, `name`, `sshHost`, `additionalArguments`).
- Files are written atomically and then restricted to `0600`. A volume that
  cannot store POSIX permissions keeps the written file and logs the failure.

## Automatic backups

- Off until the user turns them on. Turning them on without a folder opens a
  folder panel first; cancelling it leaves them off. Choosing a folder, or
  turning backups back on, writes a backup immediately.
- Saved profiles and Remote Files hosts both persist in `UserDefaults`, so
  every in-process defaults change schedules a check. The check runs once
  changes have been quiet for two seconds, at launch, before an import, and
  at quit.
- A check writes `RelayBar Backup YYYY-MM-DD HHMMSS.json` (local time) only
  when the contents' SHA-256 digest differs from the last automatic backup
  written. An empty profile and host list is never written.
- After a successful write, only regular, non-symlink files whose names match
  that exact pattern are counted, and all but the newest 30 are removed.
  Exports, other files, and folders are never removed. Removal is best effort.
- A missing backup folder is reported in Settings and never created, because
  it may be an unmounted volume. A failed write leaves the digest unrecorded,
  so the next check retries. The last successful backup time persists.

## Export

- Writes the same format to a file chosen in a save panel, suggested as
  `RelayBar Export YYYY-MM-DD.json` so it is never mistaken for an automatic
  backup. Settings reports the exported counts or the failure until it
  closes.

## Import

- Reads at most 4 MiB. The file must name the backup format and a supported
  version. Profiles decode through the saved-profile decoder, may not repeat
  an identity, and may still be unsafe to run, in which case they fail on
  their own row as saved profiles do. Hosts must pass the saved-host rules;
  repeated connections collapse to the first; more than 128 is refused. Any
  refusal names its reason and changes nothing.
- A confirmation names the file, its counts, and how many profiles (by
  identity) and hosts (by connection) are not saved yet. **Add Missing** is
  offered only when something is missing; **Replace All** is destructive.
- Add Missing appends missing profiles and hosts and leaves every saved one,
  and its lifecycle, unchanged. Replace All stops every active profile, makes
  the saved profiles and hosts exactly the backup's, and clears earlier phases
  and runtime ports. Recent connections and locations are left unchanged.
- Group tags resolve against saved and already-imported names, so an imported
  `work` joins a saved `Work`. Imported profiles never start; Start at Launch
  is restored as a preference for the next launch.
- An open Remote Files window refreshes its host list after an import.

## Ownership

- `BackupModel` owns backup settings, scheduling, and Settings-facing state
  behind the `BackupDataSource` and `BackupPanelPresenting` boundaries.
- `StoreBackupDataSource` reads and imports through `TunnelStore.shared` and
  the one app-lifetime `RemoteServerCatalog` held by
  `RemoteFilesWindowController.shared`.
- `RelayBarBackupCodec`, `BackupFileNaming`, `BackupFiles`, and `BackupCopy`
  own the format, naming and retention, file-system rules, and copy.
