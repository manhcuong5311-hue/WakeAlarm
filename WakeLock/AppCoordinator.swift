import SwiftUI
import UserNotifications
import Combine

/// Root coordinator.
/// Handles notification delivery → ring screen, Live Activity deep links,
/// force-quit detection, pending-alarm-on-launch, and burst scheduling.
final class AppCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = AppCoordinator()

    /// When set, the ring screen is presented full-screen.
    @Published var activeAlarmId: UUID? = nil

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkForAbortedAlarm()
        checkPendingAlarmOnLaunch()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is delivered while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Suppress stale burst / nag notifications that fire after the alarm was
        // already dismissed (e.g. user solved it quickly but pre-scheduled
        // notifications are still in the queue).
        let isAlarmNotification = userInfo["alarmId"] != nil
        if isAlarmNotification && !PunishmentEngine.shared.isRunning {
            completionHandler([])   // swallow silently
            return
        }

        handleAlarmNotification(userInfo)
        // Show banner + play alarm.caf even while app is foreground.
        // This is intentional: burst and nag notifications add auditory urgency
        // on top of the in-app AVAudioPlayer layers.
        completionHandler([.sound, .banner])
    }

    /// Called when the user taps a notification (app was backgrounded or killed).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleAlarmNotification(response.notification.request.content.userInfo)
        completionHandler()
    }

    // MARK: - Deep link (Live Activity "Open to Stop" button)

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "wakelock",
              url.host   == "ring",
              let idStr  = url.pathComponents.last,
              let id     = UUID(uuidString: idStr) else { return }
        activateAlarm(id: id)
    }

    // MARK: - Public

    func dismissRingScreen() {
        activeAlarmId = nil
    }

    // MARK: - Private

    private func handleAlarmNotification(_ userInfo: [AnyHashable: Any]) {
        // Every alarm-related notification (primary, burst, nag) carries alarmId.
        guard let idStr = userInfo["alarmId"] as? String,
              let id    = UUID(uuidString: idStr) else { return }

        // Show the ring screen (or bring it to front if already visible).
        activateAlarm(id: id)

        // Only schedule the burst chain if the in-app alarm engine is NOT already
        // running.  If it IS running, AVAudioPlayer handles the sound continuity
        // and the nag notifications (scheduled from AlarmRingViewModel) handle
        // further banners.  Re-scheduling here would reset the burst window and
        // potentially exceed iOS's 64-notification limit.
        guard !PunishmentEngine.shared.isRunning else { return }

        let label = AlarmManager.shared.alarms.first(where: { $0.id == id })?.label ?? ""
        NotificationService.shared.scheduleBurst(alarmIdString: idStr, label: label)
    }

    private func activateAlarm(id: UUID) {
        DispatchQueue.main.async {
            guard self.activeAlarmId != id else { return }
            self.activeAlarmId = id
        }
    }

    /// On launch, if `kAlarmInProgress` is still set the app was force-quit while
    /// an alarm was ringing — count that as a failure.
    private func checkForAbortedAlarm() {
        guard UserDefaults.standard.bool(forKey: PunishmentEngine.kAlarmInProgress) else { return }
        UserDefaults.standard.removeObject(forKey: PunishmentEngine.kAlarmInProgress)
        LiveActivityManager.shared.endActivity()
        StreakManager.shared.recordFailure()
    }

    /// On launch, look for any already-delivered alarm notification in the
    /// notification centre.  This covers two cases:
    ///  1. App was killed and the user hasn't tapped the notification yet.
    ///  2. App was backgrounded and missed the `willPresent` callback.
    ///
    /// Both burst and nag notifications carry `alarmId` so they're matched here too.
    private func checkPendingAlarmOnLaunch() {
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            guard let self,
                  let match = notifications.first(where: {
                      $0.request.content.userInfo["alarmId"] != nil
                  }) else { return }
            self.handleAlarmNotification(match.request.content.userInfo)
        }
    }
}
