# Browser Launch

The browser button opens a forwarded web endpoint without requiring the user to type its URL.

## Contract

- Browser launch exists only for a Local fixed rule with a TCP listener. SOCKS endpoints, Unix sockets, and remote listeners are never interpreted as HTTP.
- The profile-level shortcut exists only when the profile contains exactly one such rule. A rule-level menu action remains available for Local TCP rules in a multi-rule profile.
- The target is `http://<local-bind-host>:<local-port>/`.
- Missing and wildcard bind hosts (`*`, `0.0.0.0`, `::`) map to `localhost`.
- IPv6 hosts are emitted with URL brackets.
- A running profile opens immediately in the macOS default browser.
- A stopped profile starts first and opens only after all its rules reach running state.
- Starting or retrying profiles retain one pending open request.
- Stop, edit, delete, quit, or retry exhaustion cancels the pending request.

## Open on Connect

- Each profile may store one optional **Open on Connect** URL, entered in the editor's connection details.
- Only absolute `http` and `https` URLs with a host are accepted. The editor names an invalid value as the blocking issue, and a hand-edited stored value that fails this check makes the profile unsafe to run, so a saved value can never launch a file or another app's URL scheme.
- The URL is queued only when the user starts a stopped profile from its row's start button or from a group's Start All. It uses the same pending-open slot as the browser button, so it opens once all rules reach running state and is cancelled by stop, edit, delete, quit, or retry exhaustion.
- Start at Launch, the relaunch after saving an edit, automatic retries, network-change reconnects, and Restart All never queue it. A URL queued by a manual start still opens if a later retry is what reaches running state.
- Pressing the browser button on a stopped profile opens the rule's local URL instead; the Open on Connect URL is not also opened.
