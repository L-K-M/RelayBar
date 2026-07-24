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

The current model does not store custom schemes, paths, or per-tunnel launch URLs.
