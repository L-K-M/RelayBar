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

    /// The SPM test runner sets this environment variable; the packaged app
    /// never has it.
    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func notify(profileName: String, message: String) {
        // The SPM test runner has no bundle proxy: Bundle.main and
        // UNUserNotificationCenter both abort with an
        // NSInternalInconsistencyException there. Detect XCTest instead of
        // touching either API.
        guard TunnelFailureNotifier.isRunningUnderXCTest == false else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Requests added before authorization is granted are
                // dropped, so the first failure must wait for the answer.
                center.requestAuthorization(options: [.alert, .sound]) {
                    granted, _ in
                    guard granted else { return }
                    Self.add(profileName: profileName, message: message, to: center)
                }
            case .authorized, .provisional, .ephemeral:
                Self.add(profileName: profileName, message: message, to: center)
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func add(
        profileName: String,
        message: String,
        to center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(profileName) stopped retrying"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "RelayBar.tunnelFailure.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
