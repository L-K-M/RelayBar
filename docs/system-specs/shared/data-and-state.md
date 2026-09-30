# Data and State

## Persisted forwarding profile

`Tunnel` stores a stable UUID, name, optional group tag, a Start at Launch flag, an optional Open on Connect URL string, SSH destination, allowed connection arguments, ordered typed forwarding rules, optional Remote SOCKS policy, and Unix-socket settings. Each rule has a stable UUID, explicit kind, tagged TCP-or-Unix listener, and an optional tagged fixed destination.

- Storage: JSON array in `UserDefaults` under `savedTunnels.v2`.
- On the first launch under this fork's bundle identifier, saved profiles and Remote Files hosts are copied from the upstream identifier's domain `com.lx2026.RelayBar` when the key is absent here. The copy runs once, never overwrites a value already saved under this identity, and leaves the upstream domain unchanged so an upstream install keeps working.
- A group tag is either absent or a normalized string of at most 32 user-visible characters. Normalization trims surrounding whitespace and collapses internal whitespace runs. Line breaks and control characters are invalid.
- Group matching uses a locale-independent case-folded key and retains the first saved spelling. Groups are derived from profile tags; there is no separate group collection, empty-group record, index, or cache.
- Section derivation buckets profiles in one pass, sorts only distinct named groups with localized standard ordering, preserves profile order inside each bucket, and appends Ungrouped last.
- When v2 is absent, the entire `savedTunnels.v1` array must decode before each legacy tunnel is converted to one equivalent Local TCP rule and the v2 collection is written. The legacy value is retained.
- A v2 value that is present but does not decode is copied verbatim to `savedTunnels.v2.corrupt-backup` before the store falls back to legacy migration or an empty list, so the first later save cannot overwrite the only copy of the user's profiles. The backup is written once per affected launch and never read back automatically.
- Legacy UUID, name, optional group tag, SSH host, bind, ports, destination, and allowed arguments are preserved. Missing `groupTag` decodes as ungrouped, missing `additionalArguments` still decodes as an empty array, missing `startsAtLaunch` decodes as false, and missing `openOnConnectURL` decodes as unset. A present but invalid `openOnConnectURL` still decodes, so it cannot discard the saved list; the profile is instead rejected as unsafe to run.
- Runtime phase, processes, errors, retries, control paths, browser requests, owned-socket identities, and allocated remote ports are not persisted.
- A backup import replaces or extends the saved list through `TunnelStore.importProfiles(_:mode:)`; see [Backup and restore](../modules/backup.md).

## App preferences

- The popover's chosen content size is a `width`/`height` dictionary under
  `popover.contentSize.v1`, written when a resize ends. A missing, malformed,
  or non-positive value falls back to the default size.
- Backup settings live under `backup.automatic.enabled.v1`,
  `backup.folderPath.v1`, `backup.automatic.lastDigest.v1`, and
  `backup.automatic.lastDate.v1`. The folder is a plain path; RelayBar is not
  sandboxed and needs no security-scoped bookmark. Automatic backups count as
  on only while a folder path is also stored.

## Runtime ownership

`TunnelStore` is main-actor isolated and publishes saved tunnels plus phase by UUID. It separately tracks:

- desired active profiles;
- profiles whose retries ran out while still wanted, awaiting a network path change;
- master and control processes plus bounded output buffers;
- retry attempts and scheduled tasks;
- the coalescing task for a pending network-change reconnect pass;
- pending browser URLs.
- allocated remote ports by profile UUID and rule UUID;
- private control locations and app-owned local socket identities.

The store observes network path changes through an injected `NetworkPathObserving` boundary; the app supplies an `NWPathMonitor`-backed observer and tests supply a fake that fires on demand.

The desired-active state lets a retrying profile remain stoppable while no process exists. A metadata-only group mutation updates both the saved and desired-active profile copies without replacing any runtime state. Remote Files derives saved SSH connections from profile-level host and argument data and continues deduplicating equivalent connections regardless of rule count or group tag.

## Remote Files server catalog

- Standalone Remote Files hosts are JSON records in `UserDefaults` under `remoteFiles.savedServers.v1`. Each stores a stable UUID, bounded display name, validated SSH host, and safe connection arguments. The collection is capped at 128 records.
- Successful Remote Files connections are JSON records under `remoteFiles.recentServers.v1`. The newest connection is first, equivalent connections collapse by SSH host and arguments, and the collection is capped at eight records.
- Successful Remote Files roots are JSON records under
  `remoteFiles.recentLocations.v1`. Each stores a stable UUID, normalized
  absolute path, exact SSH connection identity, and bounded host display
  metadata. Equivalent connection-and-path pairs collapse and move to the
  front, direct-file opens record their parent, and the collection is capped at
  16. Failed, cancelled, or superseded opens are not recorded.
- Location history stores no listing, listed file name, remote bytes,
  credential, connection state, or upload state. Removing one location, clearing
  all locations, or removing a standalone host changes only the matching local
  records; forwarding profiles and OpenSSH config remain unchanged.
- Forwarding profiles and concrete aliases discovered from `~/.ssh/config` remain external inputs to the catalog. Config aliases are read on refresh and are not persisted as standalone RelayBar hosts.
- A backup import adds or replaces standalone hosts through the app-lifetime
  catalog under the same validity, one-record-per-connection, and 128-record
  rules, and leaves recent connections and locations unchanged.
- Remote Files directory snapshots are session-only. They are keyed by exact connection identity and normalized path, bounded by aggregate entry units, and cleared on session end; no listing or downloaded content enters `UserDefaults`.
- The combined picker order is recent, standalone saved host, forwarding profile, then OpenSSH config. The first connection at each SSH-host-and-arguments identity wins.
