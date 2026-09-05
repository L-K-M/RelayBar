# Data and State

## Persisted forwarding profile

`Tunnel` stores a stable UUID, name, optional group tag, a Start at Launch flag, SSH destination, allowed connection arguments, ordered typed forwarding rules, optional Remote SOCKS policy, and Unix-socket settings. Each rule has a stable UUID, explicit kind, tagged TCP-or-Unix listener, and an optional tagged fixed destination.

- Storage: JSON array in `UserDefaults` under `savedTunnels.v2`.
- On the first launch under this fork's bundle identifier, saved profiles and Remote Files hosts are copied from the upstream identifier's domain `com.lx2026.RelayBar` when the key is absent here. The copy runs once, never overwrites a value already saved under this identity, and leaves the upstream domain unchanged so an upstream install keeps working.
- A group tag is either absent or a normalized string of at most 32 user-visible characters. Normalization trims surrounding whitespace and collapses internal whitespace runs. Line breaks and control characters are invalid.
- Group matching uses a locale-independent case-folded key and retains the first saved spelling. Groups are derived from profile tags; there is no separate group collection, empty-group record, index, or cache.
- Section derivation buckets profiles in one pass, sorts only distinct named groups with localized standard ordering, preserves profile order inside each bucket, and appends Ungrouped last.
- When v2 is absent, the entire `savedTunnels.v1` array must decode before each legacy tunnel is converted to one equivalent Local TCP rule and the v2 collection is written. The legacy value is retained.
- A v2 value that is present but does not decode is copied verbatim to `savedTunnels.v2.corrupt-backup` before the store falls back to legacy migration or an empty list, so the first later save cannot overwrite the only copy of the user's profiles. The backup is written once per affected launch and never read back automatically.
- Legacy UUID, name, optional group tag, SSH host, bind, ports, destination, and allowed arguments are preserved. Missing `groupTag` decodes as ungrouped, missing `additionalArguments` still decodes as an empty array, and missing `startsAtLaunch` decodes as false.
- Runtime phase, processes, errors, retries, control paths, browser requests, owned-socket identities, and allocated remote ports are not persisted.

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
- Forwarding profiles and concrete aliases discovered from `~/.ssh/config` remain external inputs to the catalog. Config aliases are read on refresh and are not persisted as standalone RelayBar hosts.
- Remote Files directory snapshots are session-only. They are keyed by exact connection identity and normalized path, bounded by aggregate entry units, and cleared on session end; no listing or downloaded content enters `UserDefaults`.
- The combined picker order is recent, standalone saved host, forwarding profile, then OpenSSH config. The first connection at each SSH-host-and-arguments identity wins.
