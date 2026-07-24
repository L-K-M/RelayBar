# Process Lifecycle

`TunnelStore` runs one long-lived `/usr/bin/ssh` multiplexing master per active profile and installs its visible rules through bounded control operations.

## Launch

- The master runs with `-N`, `-T`, `BatchMode`, a 10-second connect timeout, forward-failure exit, server keepalives, `ControlPersist=no`, and `ClearAllForwardings=yes`.
- Its private control socket is created below a random app-owned `0700` temporary directory and is not shared with unrelated SSH clients.
- The master starts with no forwards. Each rule is installed in order by direct `/usr/bin/ssh -F none -S <socket> -O forward` arguments.
- Control stdout and stderr are capped at 64 KiB and each helper times out after 10 seconds.
- A profile stays Starting until every rule succeeds. Any failure or timeout terminates the master and removes all forwards rather than publishing a partially running profile.
- For each remote TCP port-`0` rule, the helper's numeric stdout is associated with that stable rule UUID. Non-numeric or ambiguous output fails startup.
- Master standard input and output are discarded; the last 16 KiB of standard error is retained for status messages.
- Local Unix listeners are preflighted before launch. RelayBar records the device and inode of sockets created by its rules and removes only a still-matching socket during cleanup.

## Recovery

- Unexpected exits retry up to 10 times.
- Delays are 1, 2, 4, 8, 16, 32, then 60 seconds for remaining attempts.
- A successful complete profile resets the retry count.
- Each retry creates a new control directory and clears prior runtime port allocations.
- Stop, edit, delete, and quit terminate the master and active helper, cancel startup and pending retries, and clean owned sockets and control files.
- Exhaustion changes the profile to failed and requires another user start.

Phases are `stopped`, `starting`, `retrying`, `running`, and `failed`.
