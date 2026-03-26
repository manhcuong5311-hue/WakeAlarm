import ActivityKit
import Foundation

/// Mirror of the main-app definition.
/// `activityType` is overridden to the same string in both targets so
/// ActivityKit correctly associates app-created activities with this widget.
struct AlarmActivityAttributes: ActivityAttributes {

    static var activityType: String { "com.SamCorp.WakeLock.AlarmActivity" }

    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable {
            case ringing
            case dismissed
        }
        var phase: Phase
        var elapsedSeconds: Int
        var escalationLevel: Int
    }

    var alarmId: String
    var alarmTime: Date
    var label: String
}
