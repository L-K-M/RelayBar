# RelayBar Privacy Policy

Effective August 14, 2026

RelayBar does not operate an account or analytics service, and it does not sell personal data. It contains no advertising, telemetry, or tracking. Its open-source Markdown packages run locally and contain no RelayBar analytics or account integration.

Tunnel names, hosts, ports, and imported safe SSH options are stored locally in RelayBar's application preferences on the user's Mac. RelayBar sends SSH connection information only to the SSH hosts that the user explicitly configures. SSH authentication is performed by the SSH client supplied by macOS using the user's normal SSH configuration, agent, and identity files. RelayBar does not request or store passwords or private-key contents.

Remote paths are kept only for the lifetime of the Remote Files window. Downloaded files are written only to a destination the user chooses. Image and Markdown previews use private temporary storage that RelayBar removes when the preview or window closes. Remote file contents are transferred only between the user's configured SSH server and Mac; RelayBar sends them to no third party.

Markdown images, embeds, wiki links, tags, HTML, and Mermaid source do not make network requests. Syntax highlighting and math rendering happen locally. RelayBar sends an HTTP, HTTPS, or email link to macOS only after the user clicks that link; the selected system browser or mail app then applies its own privacy policy.

RelayBar uses Sparkle for software updates. It contacts RelayBar's GitHub-hosted HTTPS update feed only when the user chooses **Check for Updates…** or while scheduled checks are enabled; scheduled checks run about once a week and are off by default. Enabling the schedule, or launching RelayBar with an enabled schedule when no prior check exists or the prior check is overdue, may cause a prompt background request. Update requests include no macOS system-profile fields. Like any network request, the hosting service receives ordinary connection metadata such as the source IP address. If the user accepts an offered update, Sparkle downloads the release archive referenced by the signed feed. RelayBar disables automatic update downloads and installations and verifies signed update metadata and archives before installation.

Removing RelayBar and its application data removes its saved tunnel definitions. Questions or security reports can be submitted through the project's GitHub repository.
