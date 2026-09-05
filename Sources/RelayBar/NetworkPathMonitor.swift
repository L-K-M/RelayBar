import Foundation
import Network

/// Reports network path changes so `TunnelStore` can reconnect as soon as a
/// VPN connects or disconnects, Wi-Fi returns, or the Mac rejoins a network
/// after waking — instead of sitting out the rest of a long backoff, or
/// staying failed until the user notices.
@MainActor
protocol NetworkPathObserving: AnyObject {
    /// Starts observing. `onChange` runs on the main actor once for every
    /// network path change after the first report, which only records the
    /// baseline: the network the app started on is not a change.
    func startObserving(onChange: @escaping @MainActor () -> Void)
}

/// The production observer: one `NWPathMonitor` over every interface.
///
/// Every path update after the baseline counts as a change. The interface
/// set, gateways, and status all move when a VPN's `utun` interface takes
/// over or releases the default route, and a spurious update costs only an
/// early retry of a profile that was already waiting to retry — the store
/// never touches a running master on a path change.
@MainActor
final class NetworkPathMonitor: NetworkPathObserving {
    /// Holds the system monitor so `deinit` — which is nonisolated on a
    /// main-actor class — can cancel it without reading main-actor state.
    /// `RemoteFileSSHSession.FileManagerBox` boxes a cross-isolation value
    /// for the same reason.
    private final class MonitorBox: @unchecked Sendable {
        let monitor: NWPathMonitor?

        init(_ monitor: NWPathMonitor?) {
            self.monitor = monitor
        }

        func cancel() {
            monitor?.cancel()
        }
    }

    private let box: MonitorBox
    private let queue = DispatchQueue(
        label: "com.relaybarscion.RelayBarScion.network-path"
    )
    private var onChange: (@MainActor () -> Void)?
    private var hasRecordedBaseline = false
    private var isObserving = false

    convenience init() {
        self.init(monitor: NWPathMonitor())
    }

    /// `nil` skips the system monitor so a test can drive `pathDidUpdate()`
    /// directly and check the baseline rule without a live network.
    init(monitor: NWPathMonitor?) {
        self.box = MonitorBox(monitor)
    }

    deinit {
        // Otherwise a released monitor keeps its queue alive and keeps
        // delivering updates nobody reads.
        box.cancel()
    }

    /// `NWPathMonitor.start(queue:)` raises on a second call, so observing
    /// twice replaces the callback rather than restarting the monitor.
    func startObserving(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard let monitor = box.monitor, !isObserving else { return }
        isObserving = true
        monitor.pathUpdateHandler = { [weak self] _ in
            // Bind before hopping: the task body is a Sendable closure and
            // may capture only immutable values, not the weak variable the
            // outer closure owns.
            guard let self else { return }
            Task { @MainActor in
                self.pathDidUpdate()
            }
        }
        monitor.start(queue: queue)
    }

    /// The first report describes the network the app started on; only the
    /// reports after it are changes.
    func pathDidUpdate() {
        guard hasRecordedBaseline else {
            hasRecordedBaseline = true
            return
        }
        onChange?()
    }
}
