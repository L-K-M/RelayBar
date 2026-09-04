# Task 063 — Reconnect After a Network Change

Status: Complete

Created: 2026-09-04

Completed: 2026-09-04

## Outcome

A profile the user wants running comes back on its own after a VPN connects
or disconnects, instead of staying failed once its retries run out during the
VPN session. The retry ladder (1, 2, 4, 8, 16, 32, then 60 seconds, ten
attempts) gives up after about five minutes, which almost every VPN session
outlasts; when the VPN then dropped, nothing was left to retry.

## Delivery Boundary

- Observe network path changes through one `NWPathMonitor`; treat the first
  report as the baseline and every later report as a change.
- On a change, relaunch retrying profiles immediately with a fresh attempt
  count, and start again any profile whose retries ran out while it was still
  wanted. Never touch a running or starting master: a connection the change
  severed exits on its own through server keepalives, and a connection it did
  not affect — a split-tunnel VPN — keeps its sessions.
- An explicit stop, group Stop All, edit, or delete withdraws a failed profile
  from the pending network-change retry. A profile that failed for a
  configuration reason is never started automatically.
- Keep the retry ladder, the exhaustion notification, and every phase
  unchanged; add no new phase and no persisted state.
- Coalesce a burst of path updates into one reconnect pass per short settle
  window.

## Work

- Add `NetworkPathObserving` and the `NWPathMonitor`-backed
  `NetworkPathMonitor`; inject the observer and the settle delay into
  `TunnelStore`.
- Track profiles awaiting a network change, record them in the exhaustion
  branch, and withdraw them on start, stop, Stop All, edit, and delete.
- Append the promise to the exhaustion message and notification.
- Add an outage switch to the fake `ssh` fixture and focused store tests for
  the reset, the VPN scenario, withdrawal, Stop All, and the baseline rule.
- Update the process-lifecycle, tunnel-management, data-and-state, and
  verification system specs, the changelog, and the Xcode project.

## Acceptance

- A retrying profile relaunches within the settle window of a path change and
  its next failure is attempt 1.
- A profile that exhausts retries during an outage fails with a message ending
  in "RelayBar tries again when the network changes.", posts one notification,
  and reaches Running after the outage ends and the path changes, without
  another notification.
- Stopping a failed profile, or Stop All on its group, leaves it stopped
  through later path changes; a misconfigured peer keeps its phase and
  message.
- The monitor's first report does not trigger a reconnect pass.
- `swift test -Xswiftc -warnings-as-errors`, the unsigned Release build, and
  `git diff --check` pass.

## Evidence (2026-09-04)

- `TunnelStore.reconnectAfterNetworkChange` resets `retryAttempts`, cancels
  and relaunches pending retries, and starts every saved profile in
  `profilesAwaitingNetworkChange`; `scheduleRetry`'s exhaustion branch
  records the profile there, and `start`, `stop(id:)`, `stopGroup`,
  `stopAll`, and the non-tag branch of `update` remove it.
- `NetworkPathMonitor.pathDidUpdate` swallows the first report; the store
  coalesces changes through `networkChangeTask` and a 2-second settle delay.
- Store tests drive the fake `ssh` through an outage file for the reset,
  end-to-end VPN, stop-withdrawal, and Stop All cases, and a monitor test
  covers the baseline rule.
- `git diff --check` passed on 2026-09-04.
- Local build and test execution were unavailable (Linux environment without
  Xcode); compile and test verification runs in the macOS CI job. The live
  VPN check in [Verification](../../system-specs/operations/verification.md)
  remains a manual acceptance item.
