# Security Policy

## Supported versions

Security fixes are provided for the latest released version of RelayBar.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not include private keys, passwords, production hostnames, or other secrets in a report. If private reporting is unavailable, open an issue that contains no sensitive details and request a private contact channel.

RelayBar's security boundary is intentionally narrow: it invokes `/usr/bin/ssh` for typed local, SOCKS, remote, and Unix-socket forwarding rules and `/usr/bin/sftp` for Remote Files using fixed executable paths, structured arguments, and no shell. Imported options capable of executing local commands or selecting arbitrary configuration files are rejected. Reverse SOCKS requires a visible destination policy, non-loopback listeners are called out, and RelayBar never replaces an unowned filesystem entry at a local socket path. Remote paths, listings, downloads, images, and Markdown are treated as untrusted input and bounded where RelayBar parses or renders them. Markdown HTML and Mermaid never execute, document images and embeds never load, and only user-clicked absolute web or email links reach macOS. See [the security review](docs/SECURITY_REVIEW.md) for the current threat model and residual risks.
