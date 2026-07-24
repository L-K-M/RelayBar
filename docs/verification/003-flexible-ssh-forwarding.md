# Task 003 — Flexible SSH Forwarding Verification

Verified: 2026-07-24

Result: Complete

## Automated evidence

- `swift test` passed 121 tests with 3 opt-in live tests skipped and no failures.
- Parser tests cover separate and attached `-L`, `-D`, and `-R`; mixed and repeated rules; all eight fixed TCP/Unix matrices; reverse SOCKS; remote port `0`; bracketed IPv6; quoted socket paths; structured options; remote commands; ambiguous input; unsafe paths; and blocked options.
- Model and migration tests cover v1-to-v2 conversion with stable profile data, typed JSON round trips, stable rule identities, listener conflicts, reverse-SOCKS policy, type-correct browser URLs, runtime-port presentation, tampered options, and Remote Files connection deduplication.
- The fake-SSH integration fixture verifies one forwarding-free master, ordered `-F none` control requests, mixed-rule installation, several automatic ports mapped to rule UUIDs, all-or-nothing rollback, a 10-second production control timeout, bounded retries, stop cancellation, allocation replacement after restart, browser deferral, and refusal to replace a regular file.
- The warnings-as-errors app build passed with complete Swift concurrency checking:

  ```sh
  xcodebuild -project RelayBar.xcodeproj -scheme RelayBar \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
  ```

- `plutil -lint Packaging/Info.plist` passed.
- `Tests/Fixtures/forwarding-echo.py --help` passed.

## Native UI and accessibility evidence

The DEBUG app ran with `--preview-window --flexible-forwarding-preview` in an isolated `UserDefaults` suite. Light and dark appearances were reviewed at the fixed 380-by-440 menu window size.

- The list distinguished a single Local TCP rule, a mixed three-rule profile, and a Remote SOCKS profile. Only the Local TCP profile had the top-level browser shortcut.
- The Remote SOCKS row and rule menu displayed its effective destination allowlist. The menu offered a SOCKS copy action rather than an HTTP action.
- The editor exposed Local, Local SOCKS, Remote, and Remote SOCKS types; TCP/Unix endpoint switches; the Automatic remote-port placeholder; add, duplicate, reorder, and delete controls; reverse-SOCKS policy; and Unix settings.
- Duplicating a rule produced a second independently labelled rule, exposed both move directions, and disabled Save because the listeners conflicted. Deleting it restored Save.
- A non-loopback Remote SOCKS rule displayed: “Rule 1 listens beyond loopback on the SSH server at 0.0.0.0.”
- The accessibility tree provided explicit labels for SSH command import, listener address and port, Unix paths, bind mask, reverse allowlist, add, duplicate, reorder, delete, browser, and start/stop controls.
- Importing `ssh -N -D 9999 -p 1234 user@server` produced one Local SOCKS rule on explicit `localhost:9999`, selected the correct type, preserved two SSH option values, showed the hostname-resolution guidance, and enabled Add Profile.

## Live OpenSSH evidence

Environment:

- macOS client: `/usr/bin/ssh` OpenSSH 10.2p1
- Existing test server: `spark-422e.local`
- All temporary local directories used mode `0700`. Temporary remote fixture files and sockets used unique `/tmp` paths and were removed after each check.

### RelayBar lifecycle

- `RELAYBAR_LIVE_TEST=1 RELAYBAR_LIVE_SSH_HOST=spark-422e.local swift test --filter TunnelStoreIntegrationTests/testConfiguredTunnelWhenLiveTestingIsEnabled` passed. A real RelayBar-managed Local TCP profile reached Running and returned a nonempty HTTP 200 response through the forward.
- `RELAYBAR_FLEXIBLE_LIVE_TEST=1 RELAYBAR_LIVE_SSH_HOST=spark-422e.local swift test --filter TunnelStoreIntegrationTests/testConfiguredLocalUnixSocketWhenFlexibleLiveTestingIsEnabled` passed. A real Local Unix listener reached Running with mode `0700`, and `TunnelStore.stop` removed the socket.

### SOCKS directions and policy

- A private master plus `-O forward -D localhost:<port>` carried `curl --socks5-hostname` traffic to `https://example.com/` and returned HTTP 200. The hostname was supplied to the SOCKS server, so connection and resolution occurred from the SSH-server side.
- Reverse SOCKS installed with `-R localhost:0` and returned one numeric allocated port. A server-side `curl --socks5-hostname` through that listener returned HTTP 200 for `example.com:443`.
- The same master used `PermitRemoteOpen=example.com:443`. A request for `example.org:443` failed with curl status 97, demonstrating that the reverse-SOCKS destination policy was enforced.

### Fixed TCP/Unix matrix

One private master installed all eight fixed rules through separate control requests. `Tests/Fixtures/forwarding-echo.py` provided bounded local and remote TCP/Unix echo targets. Each client sent a distinct payload and received it from the expected side:

```text
PASS local-tcp-to-remote-tcp
PASS local-tcp-to-remote-unix
PASS local-unix-to-remote-tcp
PASS local-unix-to-remote-unix
PASS remote-tcp-to-local-tcp
PASS remote-tcp-to-local-unix
PASS remote-unix-to-local-tcp
PASS remote-unix-to-local-unix
fixed_matrix=8/8 local_socket_modes=700,700 control_dir_mode=700
```

The two automatic Remote TCP listeners in this matrix returned different numeric ports and carried their corresponding payloads.

### Automatic ports, restart, and server policy

- Two remote port-`0` rules on one master returned distinct ports. A second master launch returned a fresh pair, confirming that allocations are per run rather than persisted.
- An explicit `0.0.0.0:0` remote request returned an allocated port, but `ss -ltn` on this server showed effective listeners on `127.0.0.1` and `::1`. This server does not permit a non-loopback listener through `GatewayPorts`; RelayBar therefore warns about the request and documents that the server controls the effective bind.
- Stopping raw OpenSSH left both local and remote Unix listener pathnames behind. The RelayBar live test proves its additional inode-checked cleanup for the local path. The remote path remains server-controlled and RelayBar does not claim to remove it.

## Security and boundary review

- Forwarding and control processes use fixed executable URLs and argument arrays; no RelayBar path invokes a shell.
- The master starts with `ClearAllForwardings=yes`; helpers use `-F none`, so SSH-config forwarding declarations are not silently installed with the visible profile.
- Persisted profiles are revalidated for endpoint shape, port ranges, unique rule UUIDs, listener conflicts, host safety, reverse policy, socket paths, bind mask, and allowed connection arguments before launch.
- The master control directory and live matrix directories were mode `0700`.
- Control stdout and stderr are capped, automatic-port parsing accepts only one numeric result, and a focused test proves a hung helper is terminated and rolls back the profile.
- Existing local filesystem entries are rejected before SSH runs. OpenSSH receives `StreamLocalBindUnlink=no`; a requested unlink setting is narrowed to another cleanup attempt only for a socket whose type, device, and inode RelayBar recorded during the current run.
- Local SOCKS is TCP-only and depends on the client's SOCKS hostname mode. RelayBar does not provide UDP association, a DNS listener, DNS interception, or automatic macOS proxy/resolver changes.
- Remote listener reachability, `GatewayPorts`, destination connectivity, and remote Unix cleanup remain server-controlled limitations.

No release, notarization, publication, or deployment was performed.
