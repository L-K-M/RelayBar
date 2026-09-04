# Tunnel Management

Each saved item is a forwarding profile: one SSH connection plus an ordered, non-empty collection of typed forwarding rules.

## Contract

- Users can add, edit, duplicate, delete, start, and stop profiles. Duplicating inserts an independent copy with fresh profile and rule identities directly after the original; an explicitly named profile's copy gains a " copy" suffix, the copy starts stopped, and the copy does not inherit the source's Start at Launch preference.
- Each profile has a persisted **Start at Launch** preference. The editor exposes it as a switch in the connection details, and the row menu can toggle it without changing the profile's running phase. When RelayBar launches, every saved profile with the preference on is started through the normal per-profile lifecycle; unsafe profiles fail on their own row and already-active profiles are skipped.
- Each profile may have one optional group tag. The editor places a native **Group · Optional** picker below Name, and Quick Add leaves the selected group unchanged.
- When every profile is ungrouped, the saved list keeps its original flat presentation. Once any profile has a group, named sections use localized standard ordering, preserve saved order within each section, and place **Ungrouped** last when needed.
- Row menus can move a profile to Ungrouped, an existing group, or a new inline-created group. Named section menus can rename the group or ungroup every member; no separate group records are stored.
- Named section menus also offer Start All, Stop All, and Restart All above rename and ungroup, separated and enabled by member state: Start All needs an inactive member, Stop All and Restart All need an active one. Targets are resolved by canonical group identity and snapshotted when the action begins; profiles outside the group are never affected.
- Start All starts inactive members (an unsafe member fails visibly on its own row), Stop All stops starting, retrying, and running members and also stops members whose retries ran out and that were waiting for a network change — those become Stopped — while stopped members and members that failed for other reasons keep their phase and message, and Restart All replaces each member active at invocation with one fresh launch of its current saved definition without starting stopped members.
- A rule is Local, Local SOCKS, Remote, or Remote SOCKS. Fixed Local and Remote rules independently support TCP-port and Unix-socket listeners and destinations; SOCKS listeners are TCP.
- The editor presents those four rule kinds in one full-width segmented control without a separate visible **Type** label; the control retains a rule-specific accessibility label.
- The editor can add, remove, duplicate, and reorder rules. It requires valid endpoints, unique rule identities, no overlapping listeners in the same namespace, and at least one rule. While the form is invalid, the action bar names the single first blocking issue — and the disabled Save action carries it as a tooltip — so a rejected form never goes unexplained.
- New listeners default to explicit loopback. Each explicit non-loopback listener names its rule and whether exposure is on the Mac or SSH server.
- Remote SOCKS requires an explicit Any, None, or host-and-port allowlist policy. Its effective policy remains visible in the profile summary and rule menu.
- Remote TCP port `0` means Automatic. Its allocated port is runtime-only, is shown and copyable while running, and is cleared on stop or restart.
- Profile-level Unix controls store a validated octal bind mask and whether a retry may remove a stale local socket whose type, device, and inode RelayBar recorded during the current app run. RelayBar never replaces an unowned path; remote socket cleanup remains server-controlled.
- Single Local TCP profiles retain the browser shortcut. Menus otherwise expose only type-correct copy or local-socket reveal actions. Reveal is offered from the rule's own shape rather than a filesystem probe, and falls back to the enclosing folder when the socket is already gone.
- Every row menu can copy the profile's forwarding-only `ssh` invocation — the same grammar Quick Add imports, with TCP binds named explicitly and unsafe characters backslash-escaped — so the copied command pastes back into Quick Add unchanged and runs in a shell.
- Derived sections are computed once per change to the saved list rather than per view evaluation, so phase and runtime-port updates do not rebuild them.
- Editing an active profile stops it, replaces its definition, and immediately relaunches it under the replaced definition; the editor labels its save action **Save & Restart** while the profile owns lifecycle work.
- Changing only a group tag, moving a profile, renaming a group, ungrouping members, or toggling Start at Launch from the row menu is metadata-only and preserves process phase, retries, pending browser work, runtime ports, and process ownership. Editing a profile through the editor and saving a changed Start at Launch value follows the existing edit rule for non-tag fields: an active profile is stopped and relaunched under its replacement definition.
- Deleting a profile requires a native destructive confirmation that identifies
  the profile, forwarding route, and SSH host. When the profile is starting,
  retrying, or running, the confirmation explicitly warns that deletion stops
  its active connection. Confirming cancels its connection, control operation,
  retry, pending browser launch, runtime ports, and owned temporary artifacts;
  cancelling leaves both the profile and its lifecycle untouched.
- Definitions persist immediately after add, edit, delete, move, rename, or ungroup operations.

See [Data and state](../shared/data-and-state.md) for the stored schema.
