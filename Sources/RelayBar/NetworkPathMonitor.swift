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
    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(
        label: "com.relaybarscion.RelayBarScion.network-path"
    )
    private var onChange: (@MainActor () -> Void)?
    private var hasRecordedBaseline = false

    convenience init() {
        self.init(monitor: NWPathMonitor())
    }

    /// `nil` skips the system monitor so a test can drive `pathDidUpdate()`
    /// directly and check the baseline rule without a live network.
    init(monitor: NWPathMonitor?) {
        self.monitor = monitor
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard let monitor else { return }
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.pathDidUpdate()
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
