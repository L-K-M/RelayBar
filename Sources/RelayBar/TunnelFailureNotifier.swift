import Foundation
import UserNotifications

/// Posts a single system notification when a profile exhausts automatic
/// retries, so a tunnel that gives up while the popover is closed is never
/// a silent mystery. Authorization is requested lazily on first need;
/// without it the system simply drops the notification.
@MainActor
final class TunnelFailureNotifier {
    static let shared = TunnelFailureNotifier()

    /// The SPM test runner links XCTest without a bundle proxy, and
    /// touching Bundle.main or UNUserNotificationCenter there aborts with
    /// an NSInternalInconsistencyException. XCTest's presence is the
    /// reliable signal: the packaged app never links it.
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    func notify(profileName: String, message: String) {
        // The SPM test runner has no bundle proxy: Bundle.main and
        // UNUserNotificationCenter both abort with an
        // NSInternalInconsistencyException there. Detect XCTest instead of
        // touching either API.
        guard TunnelFailureNotifier.isRunningUnderXCTest == false else { return }
        // Each closure asks for the center again rather than capturing one.
        // These completions are `@Sendable` and UNUserNotificationCenter is
        // not Sendable, so a captured center is a non-Sendable value crossing
        // an isolation boundary — an error under complete checking on SDKs
        // that carry the annotation. `current()` is a singleton accessor with
        // no isolation of its own, so re-reading it inside costs nothing and
        // hands each closure the same object without the capture.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Requests added before authorization is granted are
                // dropped, so the first failure must wait for the answer.
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound]) {
                        granted, _ in
                        guard granted else { return }
                        Self.add(profileName: profileName, message: message)
                    }
            case .authorized, .provisional, .ephemeral:
                Self.add(profileName: profileName, message: message)
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    /// Runs on arbitrary system queues via the notification-center
    /// completions and touches no actor state, so it is deliberately
    /// nonisolated (and Swift 6-clean).
    private nonisolated static func add(
        profileName: String,
        message: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(profileName) stopped retrying"
        content.body = message
        content.sound = .default
        // One identifier per profile: a newer exhaustion replaces the stale
        // banner instead of stacking duplicates in Notification Center.
        let request = UNNotificationRequest(
            identifier: "RelayBar.tunnelFailure.\(profileName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
