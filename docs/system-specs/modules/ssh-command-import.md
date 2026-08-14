# SSH Command Import

Quick Add converts a forwarding-only SSH command into one RelayBar profile without invoking a shell.

## Accepted shape

`ssh [allowed connection options] { -L rule | -D rule | -R rule }... sshHost`

## Contract

- Quoted and escaped arguments are tokenized without invoking a shell.
- Exactly one SSH destination and at least one forwarding rule are required.
- Repeated, mixed, attached, and separate `-L`, `-D`, and `-R` forms are accepted in command order.
- Fixed rules accept all OpenSSH TCP/Unix matrices: TCP-to-TCP, TCP-to-Unix, Unix-to-TCP, and Unix-to-Unix in both local and remote directions.
- `-D` becomes Local SOCKS. An `-R` listener without a destination becomes Remote SOCKS.
- Bracketed IPv6 and quoted absolute socket paths, including spaces, are preserved structurally.
- Remote TCP listener port `0` is accepted for runtime allocation; local port `0` is rejected.
- Management flags `-N`, `-T`, `-n`, and `-f` are discarded; RelayBar supplies safe process behavior.
- A restricted set of connection flags and options is preserved.
- `PermitRemoteOpen`, `StreamLocalBindMask`, and `StreamLocalBindUnlink` become validated structured profile settings.
- Omitted TCP bind addresses are normalized to explicit `localhost` in newly imported rules.
- Remote commands, multiple SSH destinations, custom config files, command-execution options, malformed rules, relative or unsafe socket paths, and ambiguous duplicate structured options are rejected.
- A connection option outside the preserved set is reported as not imported. The unsafe-option wording is reserved for values rejected on their contents, so a harmless option is never described as able to run commands or read files.
- Parsing is transactional: editor state changes only after the complete command validates.
- The same safety policy is checked again immediately before launch.

See [Security boundaries](../shared/security-boundaries.md).
