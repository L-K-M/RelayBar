import AppKit
import Combine
import SwiftUI

enum RemoteFilesWindowSizing {
    static let launcher = NSSize(width: 360, height: 300)
    static let browser = NSSize(width: 780, height: 520)
    static let browserMinimum = NSSize(width: 620, height: 400)
    static let previewPreferred = NSSize(width: 980, height: 640)
    static let previewMinimum = NSSize(width: 760, height: 440)

    static func previewSize(from current: NSSize) -> NSSize {
        NSSize(
            width: max(current.width, previewPreferred.width),
            height: max(current.height, previewPreferred.height)
        )
    }
}

@MainActor
final class RemoteFilesWindowController: NSObject, NSWindowDelegate {
    static let shared = RemoteFilesWindowController()

    private var window: NSWindow?
    private var model: RemoteFilesModel?
    private var screenObserver: AnyCancellable?
    private let serverCatalog = RemoteServerCatalog.appDefault()

    func show(
        tunnels: [Tunnel],
        service: RemoteFileServing? = nil,
        presenter: RemoteFilePresenting? = nil,
        catalog: RemoteServerCatalog? = nil
    ) {
        if let window, let model {
            model.updateTunnels(tunnels)
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let model = RemoteFilesModel(
            tunnels: tunnels,
            service: service ?? SFTPRemoteFileService(),
            presenter: presenter,
            serverCatalog: catalog ?? serverCatalog
        )
        let view = RemoteFilesView(model: model)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RemoteFilesWindowSizing.launcher),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Files"
        window.contentMinSize = RemoteFilesWindowSizing.launcher
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        window.center()

        screenObserver = model.$screen
            .removeDuplicates()
            .sink { [weak self] screen in
                Task { @MainActor [weak self] in
                    self?.resizeWindow(for: screen)
                }
            }

        self.model = model
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        model?.cancelAll()
        window?.close()
        clear()
    }

    func windowWillClose(_ notification: Notification) {
        model?.cancelAll()
        clear()
    }

    private func resizeWindow(for screen: RemoteFilesModel.Screen) {
        guard let window else { return }

        switch screen {
        case .launcher:
            window.styleMask.remove(.resizable)
            window.contentMinSize = RemoteFilesWindowSizing.launcher
            resize(window, to: RemoteFilesWindowSizing.launcher, centersWindow: true)

        case .browser:
            let wasResizable = window.styleMask.contains(.resizable)
            window.styleMask.insert(.resizable)
            window.contentMinSize = RemoteFilesWindowSizing.browserMinimum
            if !wasResizable {
                resize(window, to: RemoteFilesWindowSizing.browser, centersWindow: true)
            }

        case .preview:
            window.styleMask.insert(.resizable)
            window.contentMinSize = RemoteFilesWindowSizing.previewMinimum
            let current = window.contentView?.frame.size
                ?? window.contentRect(forFrameRect: window.frame).size
            let target = RemoteFilesWindowSizing.previewSize(from: current)
            resize(window, to: target, centersWindow: false)
        }
    }

    private func resize(
        _ window: NSWindow,
        to target: NSSize,
        centersWindow: Bool
    ) {
        guard window.contentView?.frame.size != target else { return }
        let originalCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(target)
        if centersWindow {
            window.center()
            return
        }

        let proposedFrame = NSRect(
            x: originalCenter.x - window.frame.width / 2,
            y: originalCenter.y - window.frame.height / 2,
            width: window.frame.width,
            height: window.frame.height
        )
        if let screen = window.screen {
            window.setFrame(window.constrainFrameRect(proposedFrame, to: screen), display: true)
        } else {
            window.setFrameOrigin(proposedFrame.origin)
        }
    }

    private func clear() {
        screenObserver = nil
        model = nil
        window = nil
    }
}
