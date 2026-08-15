# Process Lifecycle

`TunnelStore` runs one long-lived `/usr/bin/ssh` multiplexing master per active profile and installs its visible rules through bounded control operations.

## Launch

- The master runs with `-N`, `-T`, `BatchMode`, a 10-second connect timeout, forward-failure exit, server keepalives, `ControlPersist=no`, and `ClearAllForwardings=yes`. RelayBar also forces `ForkAfterAuthentication=no`, `PermitLocalCommand=no`, `Tunnel=no`, `GatewayPorts=no`, `ForwardAgent=no`, `ForwardX11=no`, and `ForwardX11Trusted=no` before host and connection arguments. OpenSSH therefore cannot detach the tracked child or acquire `LocalCommand`, tun, agent-forwarding, X11-forwarding, or implicit wildcard-listener authority from SSH configuration.
- Aliases, identity files, host-key policy, authentication through the user's agent, ports, users, and jump/proxy hosts still come from validated arguments and normal SSH configuration. Forcing the client `GatewayPorts` default off keeps an omitted local bind on loopback without replacing an explicitly selected non-loopback address; remote listener exposure remains subject to the server's `GatewayPorts` policy.
- Its private control socket is created below a short, atomically created app-owned `0700` temporary directory and is not shared with unrelated SSH clients. The path budget reserves Darwin's terminating NUL and OpenSSH's temporary mux-listener suffix.
- A launch waits up to 30 seconds for the control socket to appear, because the socket is published only after connection *and* authentication complete while `ConnectTimeout` bounds the TCP connect alone.
- The master starts with no forwards. Each rule is installed in order by direct `/usr/bin/ssh -F none -S <socket> -O forward` arguments.
- Control stdout and stderr are capped at 64 KiB and each helper times out after 10 seconds.
- Each launch carries a generation identifier, and every control operation is keyed by its own identifier and tagged with the launch that owns it. A stopped or replaced launch's operation can neither block nor complete the launch that replaced it, so a restart issued while a previous helper is still being reaped installs its rules normally.
- A helper's pipe handlers are detached before its remaining output is read, so one reader owns each descriptor. Output delivered after an operation completes is discarded rather than carried into the next operation.
- A profile stays Starting until every rule succeeds. Any failure or timeout terminates the master and removes all forwards rather than publishing a partially running profile.
- For each remote TCP port-`0` rule, the helper's numeric stdout is associated with that stable rule UUID. Non-numeric or ambiguous output fails startup.
- Master standard input and output are discarded; the last 16 KiB of standard error is retained for status messages.
- Local Unix listeners are preflighted before launch. RelayBar records the device and inode of sockets created by its rules and removes only a still-matching socket during cleanup.

## Recovery

- Unexpected exits retry up to 10 times.
- Delays are 1, 2, 4, 8, 16, 32, then 60 seconds for remaining attempts.
- A successful complete profile resets the retry count.
- Each retry creates a new control directory and clears prior runtime port allocations.
- Stop, edit, delete, and quit terminate the master and every helper owned by that profile, cancel startup and pending retries, and clean owned sockets and control files.
- Group-only edits and group move, rename, or ungroup actions do not stop or launch SSH. They preserve stopped, starting, retrying, running, or failed phase and all process-owned runtime state.
- Group Start All, Stop All, and Restart All snapshot the group's saved members at invocation and reuse the per-profile start and stop paths unchanged — including retry, generation, cleanup, and error behavior — so each member's outcome is independent and no second process manager or group runtime state exists.
- Exhaustion changes the profile to failed, requires another user start, and posts one system notification naming the profile and the failure (authorization requested lazily; denial is silent).

Phases are `stopped`, `starting`, `retrying`, `running`, and `failed`.

## Remote Files session

- Each Remote Files window owns at most one foreground `/usr/bin/ssh` multiplexing master for its active exact connection identity. This process is separate from every forwarding-profile master and has no forwarding rules.
- Its one-character control socket lives in a short, atomically created `0700` directory below the user's private macOS temporary directory. The path budget reserves both Darwin's terminating NUL and OpenSSH's 17-byte temporary mux-listener suffix.
- Concurrent initial SFTP operations wait on one serialized startup. The private control socket is considered ready only after it appears while the owned process is still running, with a 120-second bounded readiness ceiling. Cancelling one waiter resumes it immediately without disrupting the shared startup for other or later work.
- Listings, previews, and downloads remain independent, bounded `/usr/bin/sftp` children. Cancelling or reaping one child does not signal the master.
- Master exit removes its socket and temporary directory. There is no retry timer or background reconnect; a later explicit operation starts a replacement master.
- Server change, launcher return, Remote Files window close, and app quit synchronously retire the session so it cannot accept another channel. Process termination, reaping, and directory cleanup finish asynchronously without blocking the main actor.
