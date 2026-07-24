# Task 003 — Flexible SSH Forwarding Profiles

Status: Complete

Created: 2026-07-24

Completed: 2026-07-24

## Outcome

Replace the assumption that one saved item is one local TCP (`-L`) forward with a forwarding profile: one SSH connection plus one or more typed forwarding rules.

A profile supports every structured forwarding form exposed by OpenSSH `ssh(1)`:

- local forwarding (`-L`) between any supported TCP-port and Unix-socket listen/destination combination;
- local dynamic SOCKS4/SOCKS5 forwarding (`-D`);
- remote forwarding (`-R`) between any supported TCP-port and Unix-socket listen/destination combination;
- remote dynamic SOCKS4/SOCKS5 forwarding (`-R` without a fixed destination);
- repeated and mixed rules on one managed SSH connection;
- OpenSSH-assigned remote TCP listen port `0`, with the allocated port reported in RelayBar at runtime.

RelayBar can import, edit, run, stop, monitor, and retry commands such as:

```sh
ssh -N -D 9999 -p 1234 user@server
ssh -N -L 8080:localhost:3000 -D 1080 -R 9000:localhost:9000 user@server
ssh -N -L /tmp/relaybar.sock:/var/run/service.sock -R 0:localhost:3000 user@server
ssh -N -R 1081 user@server
```

Dynamic forwarding uses OpenSSH as a SOCKS server. A SOCKS client can send destination hostnames through the proxy for resolution on the connection-opening side, but RelayBar does not become a DNS server and cannot force an application to proxy its DNS lookups.

The forwarding semantics in this task follow the OpenSSH [`ssh(1)` forwarding options](https://man.openbsd.org/ssh#D) and [`ssh_config(5)` forwarding directives](https://man.openbsd.org/ssh_config#DynamicForward).

## Delivery Boundary

### Included

- A versioned, typed profile model with stable profile and rule identities.
- Every documented TCP-port and Unix-socket form of local, local-dynamic, remote, and remote-dynamic forwarding.
- One or more repeated or mixed forwarding rules per profile.
- Quick Add support for separate and attached `-L`, `-D`, and `-R` forms.
- Manual creation, editing, removal, and ordering of all supported rules and endpoint types.
- Remote TCP listen port `0` allocation and runtime presentation.
- Existing allowed SSH connection options plus the structured options needed to control Unix-socket permissions, stale-socket handling, and reverse-SOCKS destinations.
- One long-lived `/usr/bin/ssh` connection per profile plus bounded OpenSSH control operations needed to install and inspect its rules.
- Migration of every existing saved tunnel to a one-rule local TCP profile without data loss.
- Rule-aware menu-bar summaries, runtime endpoints, exposure warnings, validation, tests, system documentation, and verification evidence.

### Excluded

- UDP forwarding, SOCKS5 UDP association, a local DNS listener, DNS interception, or a DNS-over-HTTPS service because ordinary OpenSSH forwarding does not provide them.
- Automatically changing macOS system proxy or resolver settings; applications remain responsible for selecting and correctly using a SOCKS endpoint.
- X11, SSH-agent, and tunnel-device forwarding because they are not `-L`, `-D`, or `-R` port-forwarding rules.
- Remote commands, interactive shells, arbitrary SSH options, `ProxyCommand`, user-selected config files, or invoking a shell.
- Importing forwarding declarations that exist only in the user's SSH config. RelayBar-managed profiles contain only the rules visible in RelayBar while retaining normal SSH connection, identity, agent, host-key, and jump-host configuration.
- Deployment or publication.

## Work

### 1. Introduce typed forwarding profiles

- Replace destination fields on the root saved item with a non-empty ordered collection of tagged forwarding rules.
- Represent a TCP endpoint as an optional bind address plus a port, and a Unix endpoint as a path.
- Represent four rule kinds explicitly:
  - local fixed forwarding from a local TCP or Unix listener to a remote TCP or Unix destination;
  - local dynamic SOCKS forwarding from a local TCP listener;
  - remote fixed forwarding from a remote TCP or Unix listener to a local TCP or Unix destination;
  - remote dynamic SOCKS forwarding from a remote TCP listener.
- Do not encode dynamic forwarding or Unix sockets with empty host, port, or destination sentinels.
- Store a runtime-assigned remote port separately from the persisted request for port `0`; clear it on stop and replace it after every successful restart.
- Keep display formatting, OpenSSH argument generation, validation, migration, and allocated-port state outside SwiftUI views.
- Decode the current `savedTunnels.v1` representation and migrate each item to one equivalent local TCP rule while preserving its UUID, name, SSH host, bind address, ports, and additional arguments.
- Persist the new schema under a new versioned key only after the complete old collection decodes and converts successfully.
- Keep saved SSH connections usable by Remote Files and preserve its exact SSH-host and argument deduplication behavior.

### 2. Generalize Quick Add

- Parse exactly one SSH destination and at least one supported forwarding rule without invoking a shell.
- Accept repeated, mixed, attached, and separate `-L`, `-D`, and `-R` forms before the SSH destination.
- Cover every documented fixed-forward matrix:
  - local TCP to remote TCP;
  - local TCP to remote Unix;
  - local Unix to remote TCP;
  - local Unix to remote Unix;
  - remote TCP to local TCP;
  - remote TCP to local Unix;
  - remote Unix to local TCP;
  - remote Unix to local Unix.
- Distinguish a fixed remote forward from `-R [bind_address:]port` reverse SOCKS without relying on empty parsed fields.
- Accept remote TCP listen port `0` only where OpenSSH documents runtime allocation.
- Parse bracketed IPv6 addresses without confusing address colons with forwarding separators, and parse socket paths as one structured argument even when they contain spaces.
- Continue discarding management flags that RelayBar supplies, including `-N`, `-T`, `-n`, and `-f`.
- Preserve only connection arguments allowed by `SSHArgumentPolicy`. Parse `PermitRemoteOpen`, `StreamLocalBindMask`, and `StreamLocalBindUnlink` into validated structured settings rather than retaining unchecked strings.
- Reject remote commands, missing values, malformed ports, unsafe paths or options, unsupported forwarding shapes, and ambiguous input with rule-specific errors.
- Populate the editor only after the entire command validates so a failed import cannot leave a partial profile.

### 3. Make the editor rule-based

- Keep profile name and SSH host as connection-level fields.
- Present an ordered forwarding-rules list with explicit **Local**, **Local SOCKS**, **Remote**, and **Remote SOCKS** types.
- Let fixed Local and Remote rules independently choose TCP port or Unix socket for their listener and destination.
- Limit both SOCKS rule types to the TCP listener shapes supported by OpenSSH.
- Show directional field labels that identify which endpoint exists on the Mac, SSH server, or forwarding destination side.
- Allow add, remove, duplicate, and reorder while requiring at least one valid rule.
- Present remote port `0` as **Automatic** and reserve space for the allocated runtime endpoint.
- Default new TCP listeners to loopback. Preserve explicitly imported non-loopback or wildcard binds and show a prominent exposure warning.
- For reverse SOCKS, require either an explicit destination allowlist or an explicit **Any destination** choice. Model this as a profile-level policy because OpenSSH `PermitRemoteOpen` applies to the connection rather than one rule.
- Expose Unix-socket bind mask and stale-socket replacement as advanced structured controls with their filesystem effects explained before save.
- Explain that SOCKS hostname resolution depends on client behavior and that server policy controls remote listeners.

### 4. Make menu actions match the rule type

- Keep start, stop, retry, edit, and delete at profile level because all rules share one SSH connection and fate.
- Show a single rule's direction and endpoints directly; summarize a multi-rule profile by rule count and SSH destination while keeping its full rule list in the editor.
- Preserve the one-click browser action only when there is one unambiguous local TCP fixed-forward endpoint.
- Provide rule-aware endpoint actions:
  - local TCP fixed-forward endpoints can open in a browser or be copied;
  - local SOCKS endpoints can be copied;
  - local Unix-socket paths can be copied or revealed when present;
  - remote fixed and reverse-SOCKS listeners can be copied;
  - automatic remote ports expose the currently allocated endpoint only while running.
- Never present a SOCKS endpoint, Unix socket, or remote listener as an HTTP URL.

### 5. Install all rules on one managed connection

- Use a private, app-owned OpenSSH control socket or an equivalently reliable structured mechanism to keep one long-lived SSH connection while installing rules individually.
- Start the long-lived connection with RelayBar's non-interactive safety and lifecycle options and with configuration-defined forwardings cleared, so the profile runs only its visible typed rules.
- Install each rule through bounded `/usr/bin/ssh` control operations without invoking a shell. Suppress user-config forwarding declarations on those helper operations while retaining the established authenticated connection.
- Capture the machine-usable result of each remote port-`0` request and associate the allocated port with the correct stable rule identity, including when several automatic rules exist.
- Keep the profile in **Starting** until every rule is installed. If any rule fails, stop the connection, revoke already installed rules, clean up owned local socket artifacts, and retry the complete profile under the existing bounded policy.
- Continue supplying batch mode, connection timeout, forward-failure handling, server keepalives, bounded output, cancellation, and direct `/usr/bin/ssh` execution.
- Stop an active profile before replacing its definition. Stop, edit, delete, quit, failed startup, and retry cancellation must terminate the owned connection and helper operations and remove the private control socket.
- Detect duplicate or overlapping listen endpoints within a profile before launch. Treat operating-system, other-process, and server-side conflicts reported by OpenSSH as runtime failures.
- Verify the control workflow and every forwarding form on the minimum supported macOS OpenSSH version.

### 6. Handle Unix-socket lifecycle safely

- Require explicit, normalized paths and reject NULs, control characters, option-shaped values, and paths that cannot be represented safely as direct process arguments.
- Treat local and remote socket paths as distinct namespaces and label them accordingly.
- Never replace a regular file, directory, symlink, or socket not proven to be RelayBar-owned.
- If stale-socket replacement is enabled, preflight the local path, constrain deletion to the exact configured socket path, explain the risk, and record whether cleanup is app-owned.
- Apply the configured local stream-socket bind mask deterministically and test the resulting permissions.
- Remove app-owned local socket artifacts on stop, failure, cancellation, retry, edit, delete, and quit.
- Report remote socket cleanup as server-controlled and never claim that a remote path was removed without evidence.

### 7. Preserve the security boundary

- Validate every persisted profile and structured option again immediately before launch.
- Normalize omitted binds on newly imported local `-L` and `-D` listeners to explicit loopback so `GatewayPorts` cannot silently widen a RelayBar-managed local listener.
- Permit explicit non-loopback local binds only with the existing visible exposure warning.
- Warn that a reachable local SOCKS listener lets its clients request outbound TCP connections from the SSH server.
- Default remote TCP listeners to remote loopback. Warn that remote forwarding can expose Mac-side destinations and that non-loopback remote binds may require server-side `GatewayPorts`.
- Warn that reverse SOCKS lets remote clients request outbound TCP connections from the Mac's network position. Validate and display the effective `PermitRemoteOpen` policy whenever a reverse-SOCKS rule exists.
- Keep option-shaped hosts, unsafe socket paths, control characters, invalid ports, executable options, log-file options, and arbitrary configuration-file selection blocked.
- Store private control sockets in a `0700` app-owned temporary directory and prevent connection sharing with unrelated SSH processes.
- Document that listener setup success does not guarantee later connectivity to requested fixed or SOCKS destinations.

### 8. Document and verify

- Update tunnel-management, command-import, data/state, process-lifecycle, security, verification, README, and user-facing examples only when the behavior is implemented.
- Document local SOCKS hostname delegation with an example such as `curl --socks5-hostname 127.0.0.1:9999 https://example.com`.
- Document the inverse resolution and egress direction for reverse SOCKS, Unix-socket ownership limitations, remote `GatewayPorts`, and runtime port allocation.
- Record focused unit, migration, parser-matrix, process/control, UI, accessibility, filesystem, security, and live-SSH evidence in `docs/verification/003-flexible-ssh-forwarding.md`.

## Acceptance

- Quick Add imports `ssh -N -D 9999 -p 1234 user@server` as one local SOCKS rule on port 9999 while preserving SSH port 1234.
- Quick Add imports `ssh -N -R 1081 user@server` as reverse SOCKS rather than rejecting it or inventing a fixed destination.
- Quick Add and manual editing cover all eight fixed TCP/Unix listen-to-destination combinations, local SOCKS, reverse SOCKS, repeated rules, mixed rules, attached options, and bracketed IPv6.
- A command containing multiple mixed `-L`, `-D`, and `-R` rules round-trips through the typed model without changing its forwarding meaning.
- Existing saved tunnels migrate to equivalent one-rule local profiles with stable UUIDs and no loss of names, endpoints, bind addresses, SSH hosts, or allowed SSH arguments.
- A user can create, edit, duplicate, reorder, and remove every included rule type, but cannot save a profile with no rules, invalid endpoints, unsafe socket paths, or an unspecified reverse-SOCKS destination policy.
- One start action establishes one long-lived SSH connection and every rule; one stop action and app quit terminate the connection, its control operations, and pending retries.
- A failure while installing any rule rolls back the entire startup instead of reporting a partially running profile as healthy.
- Each remote port-`0` rule displays its correct allocated port while running, copy actions use that port, retries may replace it, and stopped profiles do not retain stale runtime allocations.
- Several remote port-`0` rules in one profile map their allocated ports to the correct rule identities without parsing ambiguous or localized diagnostic prose.
- Single-local-TCP profiles retain their browser shortcut. Every other endpoint has a type-correct copy or reveal action and is never misrepresented as HTTP.
- Bind warnings identify every explicit non-loopback local or remote listener. Reverse SOCKS always displays whether destinations are restricted or unrestricted.
- Existing non-socket filesystem entries are never deleted. App-owned local sockets and private control sockets have verified permissions and cleanup behavior across success, failure, cancellation, retry, edit, delete, and quit.
- A real local SOCKS rule carries TCP traffic and resolves a client-supplied hostname from the SSH server side.
- A real reverse-SOCKS rule carries TCP traffic in the opposite direction, enforces its configured `PermitRemoteOpen` policy, and is tested with remote loopback and an explicitly permitted non-loopback listener where server policy allows.
- All eight fixed TCP/Unix forwarding combinations are covered by argument tests; every combination supported by the live test server is exercised end to end, with unsupported server capabilities recorded rather than silently skipped.
- Real remote port-`0` allocation is exercised across start, stop, and retry, including multiple automatic rules when supported by the minimum macOS OpenSSH client.
- Documentation states that SOCKS client modes may resolve names on different sides, RelayBar cannot control client DNS behavior, and OpenSSH forwarding is not a general DNS or UDP proxy.
- Malformed specifications, multiple SSH destinations, remote commands, blocked options, tampered persisted rules, unsafe socket replacement, and unsupported forwarding features are rejected without invoking a shell.
- SSH-config forwarding declarations are not silently added to a RelayBar profile or started alongside its visible rules.
- Remote Files continues to derive deduplicated saved-server choices from migrated and multi-rule profiles.
- Unit tests, migration tests, parser round trips, argument/control tests, `swift test`, the warnings-as-errors app build, `plutil -lint`, and `git diff --check` pass.
- Current system specs and `docs/verification/003-flexible-ssh-forwarding.md` describe the implemented behavior, security decisions, live-SSH results, and any server-controlled limitations.
- No release, notarization, publication, or deployment occurs without separate explicit approval.

## Completion Artifacts

- Typed forwarding-profile, endpoint, rule, structured-option, and runtime-allocation model with legacy migration
- Generalized SSH command parser, rule editor, menu actions, and managed control workflow
- Focused automated, filesystem, and live-SSH tests
- Updated system specs, security review, README, and user documentation
- `docs/verification/003-flexible-ssh-forwarding.md`

Completion evidence is recorded in
[`docs/verification/003-flexible-ssh-forwarding.md`](../../verification/003-flexible-ssh-forwarding.md).
