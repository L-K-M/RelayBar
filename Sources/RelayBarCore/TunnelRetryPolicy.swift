import Foundation

/// Backoff shared by the macOS store and the Linux supervisor so both front
/// ends retry a failing profile on the same schedule before giving up:
/// 1s, 2s, 4s … capped at one minute.
public enum TunnelRetryPolicy {
    public static let defaultMaxAttempts = 10

    public static func delay(for attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 6)
        var delay: TimeInterval = 1
        for _ in 0..<exponent where delay < 60 {
            delay *= 2
        }
        return min(delay, 60)
    }
}
