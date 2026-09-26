# Task 065 — Middle Truncation and Open on Connect

Status: In Progress

Created: 2026-09-26

## Outcome

Profiles whose names differ only at the end stay distinguishable in the
popover, and a profile can open a chosen web page when the user starts it.

## Delivery Boundary

- Row names and forwarding summaries truncate in the middle instead of at
  the end. Other popover text keeps its current truncation.
- Add one optional per-profile **Open on Connect** URL, limited to absolute
  `http` and `https` URLs with a host.
- Open it only for starts the user makes from the row start button or a
  group's Start All, after every rule reaches Running. Start at Launch, edit
  relaunches, retries, network reconnects, and Restart All never open it.
- Do not change what the browser button opens.

## Work

- Add `Tunnel.openOnConnectURL`, decoded with an unset default, and include
  its validity in `isSafeToRun`.
- Add `OpenOnConnectURL` validation shared by the editor and the store.
- Queue the URL through the existing pending-browser slot from the manual
  start paths in `TunnelStore`.
- Add the editor field and its blocking-issue message.
- Update the browser-launch, tunnel-management, and data-and-state specs.
- Add validation, decoding, and store lifecycle tests.

## Acceptance

- Two long names that differ only in their last characters show different
  visible text in the popover.
- Starting a profile with a URL from its row opens the URL once, only after
  it is Running; stopping before Running opens nothing.
- Start at Launch and saving an edit of a running profile do not open it.
- The editor blocks non-HTTP schemes, missing hosts, and embedded spaces
  with a named reason; profiles saved without the field load unchanged.
- `swift test -Xswiftc -warnings-as-errors`, the Release build, and
  `git diff --check` pass.
