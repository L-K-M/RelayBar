# RelayBar Privacy Policy

Effective July 24, 2026

RelayBar does not collect, sell, or share personal data. It contains no analytics, advertising, telemetry, tracking, or accounts. Its open-source Markdown packages run locally and contain no RelayBar analytics or account integration.

Tunnel names, hosts, ports, and imported safe SSH options are stored locally in RelayBar's application preferences on the user's Mac. RelayBar sends connection information only to the SSH hosts that the user explicitly configures. SSH authentication is performed by the SSH client supplied by macOS using the user's normal SSH configuration, agent, and identity files. RelayBar does not request or store passwords or private-key contents.

RelayBar keeps at most 16 successfully opened remote folder locations in local
application preferences. Each recent location contains the normalized absolute
path, the exact SSH host connection identity, and local display metadata; it
does not contain directory listings, remote file contents, credentials, or
connection state. A user can remove one recent location or clear all recent
locations. Downloaded files are written only to a destination the user chooses.
Uploads read only the one local file the user chooses and send it to the open
SSH folder through a hidden remote staging name. Image and Markdown previews
use private temporary storage that RelayBar removes when the preview or window
closes. Remote file contents are transferred only between the user's configured
SSH server and Mac; RelayBar sends them to no third party.

Markdown images, embeds, wiki links, tags, HTML, and Mermaid source do not make network requests. Syntax highlighting and math rendering happen locally. RelayBar sends an HTTP, HTTPS, or email link to macOS only after the user clicks that link; the selected system browser or mail app then applies its own privacy policy.

Removing RelayBar and its application data removes its saved tunnel definitions. Questions or security reports can be submitted through the project's GitHub repository.
