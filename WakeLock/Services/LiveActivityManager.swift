import ActivityKit
import Foundation

/// Manages the WakeLock Live Activity lifecycle.
///
/// Responsibilities:
/// - Start a Live Activity when an alarm begins ringing
/// - Push content-state updates as punishment phases escalate
/// - End the activity (with .immediate dismissal) when the alarm is dismissed
///
/// All public methods are safe to call regardless of device support;
/// they silently no-op when Live Activities are unavailable.
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<AlarmActivityAttributes>?

    // MARK: - Public API

    /// Start a new Live Activity for the given alarm.
    /// Any previously running activity is ended first.
    func startActivity(for alarm: Alarm) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities disabled or unsupported.")
            return
        }

        // Terminate any stale activity from a previous alarm
        endActivity()

        let attributes = AlarmActivityAttributes(
            alarmId:   alarm.id.uuidString,
            alarmTime: alarm.time,
            label:     alarm.label.isEmpty ? "Wake Up!" : alarm.label
        )
        let initialState = AlarmActivityAttributes.ContentState(
            phase:           .ringing,
            elapsedSeconds:  0,
            escalationLevel: 1
        )
        let content = ActivityContent(
            state:     initialState,
            staleDate: Date().addingTimeInterval(600) // stale after 10 min
        )

        do {
            activity = try Activity<AlarmActivityAttributes>.request(
                attributes: attributes,
                content:    content,
                pushType:   nil   // local-only; no push token needed
            )
            print("[LiveActivityManager] Activity started: \(activity?.id ?? "?")")
        } catch {
            print("[LiveActivityManager] Start error: \(error)")
        }
    }

    /// Push an escalation update.  Called from PunishmentEngine on phase changes.
    func update(elapsedSeconds: Int, escalationLevel: Int) {
        guard let activity else { return }
        let state = AlarmActivityAttributes.ContentState(
            phase:           .ringing,
            elapsedSeconds:  elapsedSeconds,
            escalationLevel: escalationLevel
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
            )
        }
    }

    /// End the Live Activity and remove it from the lock screen immediately.
    func endActivity() {
        guard let activity else { return }
        let finalState = AlarmActivityAttributes.ContentState(
            phase:           .dismissed,
            elapsedSeconds:  0,
            escalationLevel: 1
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            self.activity = nil
        }
    }
}
