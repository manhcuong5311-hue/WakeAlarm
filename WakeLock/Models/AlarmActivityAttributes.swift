import ActivityKit
import Foundation

/// Shared ActivityAttributes for the WakeLock Live Activity.
///
/// This struct is defined identically in both the main app target and the
/// WakeLockWidget extension target. The `activityType` is overridden to the
/// same fixed string in both so ActivityKit can match app-created activities
/// to the widget's ActivityConfiguration.
struct AlarmActivityAttributes: ActivityAttributes {

    // Override so both module copies map to the same activity type identifier.
    static var activityType: String { "com.SamCorp.WakeLock.AlarmActivity" }

    // MARK: - Dynamic (per-update) state

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable {
            case ringing    // alarm is actively ringing
            case dismissed  // user dismissed – activity ending
        }

        var phase: Phase
        /// Seconds since the alarm started ringing
        var elapsedSeconds: Int
        /// 1 = normal, 2 = escalated (30s+), 3 = aggressive (60s+)
        var escalationLevel: Int
    }

    // MARK: - Static (set-once at activity creation)

    /// UUID string of the firing alarm – used in the deep-link URL
    var alarmId: String
    /// Scheduled fire time (used to display the clock face)
    var alarmTime: Date
    /// User-defined alarm label (e.g. "Morning Workout")
    var label: String
}
