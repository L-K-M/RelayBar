# Security Boundaries

- RelayBar invokes `/usr/bin/ssh` directly and never invokes a shell.
- Remote Files invokes `/usr/bin/sftp` directly with structured arguments and batch input; it also never invokes a shell.
- Host values cannot be empty, option-shaped, whitespace-separated, or contain control characters.
- Additional arguments must match the explicit allowlist in `SSHArgumentPolicy`; values must be nonempty and contain no control or newline characters.
- Options that execute commands, choose arbitrary config files, or write logs are blocked.
- SSH uses batch mode; password prompts are unsupported.
- Normal SSH configuration, known hosts, identity files, and the user's SSH agent remain available.
- Remote paths must be absolute, single-line, and no more than 32 KiB of UTF-8. SFTP batch values escape quotes and backslashes. Listing basenames containing path separators or control characters are ignored; absolute listing names are accepted only when they resolve to direct children of the requested folder.
- Remote listings are capped at 10,000 supported entries, 32 KiB per line, and 4 KiB per entry name; negative sizes are rejected. Captured SFTP output is capped at 32 MiB, captured SFTP diagnostics at 1 MiB, image previews at 100 MiB, and Markdown previews at 2 MiB.
- Command output and previews use private temporary directories. Downloads use a hidden `0700` staging directory beside the chosen destination and replace existing content only after success.
- Cancellation, failure, preview exit, window close, and app quit clean up owned temporary content.
- Markdown accepts UTF-8 without NULs. HTML-looking spans, including multi-line tags and tags in link labels, are escaped before parsing so raw tags stay literal and never execute; images and embeds never load; Mermaid never executes.
- Only clicked absolute HTTP, HTTPS, and email links without credentials or raw/percent-decoded control characters reach macOS. Relative Markdown references apply the same decoded-control rejection. Private wiki, tag, footnote, and math references require a random per-preview capability token; remote-authored forgeries remain blocked.
- Syntax highlighting is limited to 64 KiB from an explicit supported language and 128 labelled blocks per document, using a bundled highlighter without DOM or network access.
- Math is syntax-validated and limited to 4,096 characters per formula, 256 formulas per document, and bounded output dimensions. Named and inline footnotes, internal links, and embed placeholders are also count-bounded; invalid and overflow content remains readable source.
- Rendering dependencies use exact package versions and their notices are bundled with the app.
- RelayBar never reads, copies, logs, or stores private-key contents.
- Non-loopback bind addresses are called out in the editor.
- Browser launch fixes the scheme to HTTP and falls back to `localhost` when a bind host cannot form a valid URL.

Detailed threat review: [Security review](../../SECURITY_REVIEW.md).
