import Foundation
import UserNotifications

/// Posts a single system notification when a profile exhausts automatic
/// retries, so a tunnel that gives up while the popover is closed is never
/// a silent mystery. Authorization is requested lazily on first need;
/// without it the system simply drops the notification.
@MainActor
final class TunnelFailureNotifier {
    static let shared = TunnelFailureNotifier()

    private var requestedAuthorization = false

    func notify(profileName: String, message: String) {
        // Test binaries have no bundle proxy; UNUserNotificationCenter
        // aborts with an NSInternalInconsistencyException without one.
        guard Bundle.main.bundleIdentifier != nil else { return }
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "\(profileName) stopped retrying"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "RelayBar.tunnelFailure.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
