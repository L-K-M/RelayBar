# Application Shell

RelayBar is a native SwiftUI `MenuBarExtra` application for macOS 13 or newer.

## Contract

- The app runs as a menu-bar accessory with no Dock icon (`LSUIElement`).
- The popover is a 380 × 440 point window containing the tunnel list or editor.
- The menu-bar icon indicates whether any tunnel is starting, retrying, or running.
- The list header reports the active tunnel count.
- A labeled Remote Files row below the tunnel list opens or focuses one separate window.
- The Remote Files window uses a 360 × 300 point launcher and expands to 780 × 520 points for browsing and preview, with a 620 × 400 minimum after opening.
- Quit stops all managed SSH processes before terminating the app.

## Ownership

- `RelayBarApp` owns application lifecycle.
- `RelayBarRootView` owns navigation and presentation.
- `TunnelStore.shared` owns tunnel and process state.
- `RemoteFilesWindowController.shared` owns the Remote Files window.
