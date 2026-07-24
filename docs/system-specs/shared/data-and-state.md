# Data and State

## Persisted forwarding profile

`Tunnel` stores a stable UUID, name, SSH destination, allowed connection arguments, ordered typed forwarding rules, optional Remote SOCKS policy, and Unix-socket settings. Each rule has a stable UUID, explicit kind, tagged TCP-or-Unix listener, and an optional tagged fixed destination.

- Storage: JSON array in `UserDefaults` under `savedTunnels.v2`.
- When v2 is absent, the entire `savedTunnels.v1` array must decode before each legacy tunnel is converted to one equivalent Local TCP rule and the v2 collection is written. The legacy value is retained.
- Legacy UUID, name, SSH host, bind, ports, destination, and allowed arguments are preserved. Missing `additionalArguments` still decode as an empty array.
- Runtime phase, processes, errors, retries, control paths, browser requests, owned-socket identities, and allocated remote ports are not persisted.

## Runtime ownership

`TunnelStore` is main-actor isolated and publishes saved tunnels plus phase by UUID. It separately tracks:

- desired active profiles;
- master and control processes plus bounded output buffers;
- retry attempts and scheduled tasks;
- pending browser URLs.
- allocated remote ports by profile UUID and rule UUID;
- private control locations and app-owned local socket identities.

The desired-active state lets a retrying profile remain stoppable while no process exists. Remote Files derives saved SSH connections from profile-level host and argument data and continues deduplicating equivalent connections regardless of rule count.
