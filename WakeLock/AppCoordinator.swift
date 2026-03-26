import SwiftUI
import UserNotifications
import Combine
import UIKit

/// Root coordinator.
///
/// Responsibilities:
/// - Notification delivery → ring screen presentation
/// - Rolling burst-notification chain (infinite window until QR scan)
/// - Force-quit / memory-pressure kill recovery (re-rings within 15 min)
/// - Live Activity deep-link handling (`wakelock://ring/<uuid>`)
/// - Pending-alarm-on-launch detection
final class AppCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = AppCoordinator()

    /// When non-nil the ring screen is presented full-screen.
    @Published var activeAlarmId: UUID? = nil

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkForAbortedAlarm()
        checkPendingAlarmOnLaunch()

        // Re-run the active-alarm check every time the app comes to the
        // foreground — covers the case where the user opens the app directly
        // (via app switcher or icon tap) instead of tapping the notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // =========================================================================
    // MARK: - UNUserNotificationCenterDelegate
    // =========================================================================

    /// Called when a notification fires while the app is in the **foreground**.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Suppress burst / nag notifications that fire after the alarm was already
        // dismissed (stale pre-scheduled notifications still in the system queue).
        let isAlarmRelated = userInfo["alarmId"] != nil
        if isAlarmRelated && !PunishmentEngine.shared.isRunning {
            completionHandler([])
            return
        }

        handleAlarmNotification(userInfo, notificationId: notification.request.identifier)

        // Show banner + play alarm.caf even while the app is in the foreground.
        // This is intentional: burst and nag banners add auditory urgency on top
        // of the in-app AVAudioPlayer layers.
        completionHandler([.sound, .banner])
    }

    /// Called when the user **taps** a notification (app was backgrounded or killed).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleAlarmNotification(
            response.notification.request.content.userInfo,
            notificationId: response.notification.request.identifier
        )
        completionHandler()
    }

    // =========================================================================
    // MARK: - Deep link  (Live Activity "Open to Stop" button)
    // =========================================================================

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "wakelock",
              url.host   == "ring",
              let idStr  = url.pathComponents.last,
              let id     = UUID(uuidString: idStr) else { return }
        activateAlarm(id: id)
    }

    // =========================================================================
    // MARK: - Public
    // =========================================================================

    func dismissRingScreen() {
        activeAlarmId = nil
    }

    // =========================================================================
    // MARK: - Private: notification routing
    // =========================================================================

    /// Central handler called from both `willPresent` and `didReceive`.
    ///
    /// Rolling-burst logic:
    /// - First fire (engine NOT running): show ring screen + schedule burst chain.
    /// - Subsequent burst fires (engine IS running): reschedule burst chain to
    ///   extend the notification window by another `burstCount × burstInterval`
    ///   seconds.  This creates an infinite rolling window — the burst chain
    ///   never expires as long as the alarm is still ringing.
    private func handleAlarmNotification(
        _ userInfo: [AnyHashable: Any],
        notificationId: String = ""
    ) {
        guard let idStr = userInfo["alarmId"] as? String,
              let id    = UUID(uuidString: idStr) else { return }

        // Show the ring screen (no-op if already visible)
        activateAlarm(id: id)

        // Detect any burst notification type:
        // - "-burst-N"  = reactive burst (scheduled while app was foreground)
        // - "-pburst-N" = pre-emptive burst (scheduled at alarm-creation time)
        // Both carry notificationType="burst" in userInfo — prefer that check.
        let notifType = userInfo["notificationType"] as? String
        let isBurst = notifType == "burst"
                   || notificationId.contains("-burst-")
                   || notificationId.contains("-pburst-")

        if PunishmentEngine.shared.isRunning {
            // Alarm is already active in-app.
            // Only act on burst notifications — reschedule to keep the chain alive.
            if isBurst {
                let label = AlarmManager.shared.alarms
                    .first(where: { $0.id == id })?.label ?? ""
                NotificationService.shared.scheduleBurst(
                    alarmIdString: idStr,
                    label: label
                )
                print("[AppCoordinator] Burst fired — rolling window extended")
            }
            return
        }

        // Engine is NOT running yet (first delivery, process was killed, or cold launch).
        // Schedule the initial reactive burst chain (supplements pre-emptive bursts).
        let label = AlarmManager.shared.alarms
            .first(where: { $0.id == id })?.label ?? ""
        NotificationService.shared.scheduleBurst(alarmIdString: idStr, label: label)
    }

    private func activateAlarm(id: UUID) {
        DispatchQueue.main.async {
            guard self.activeAlarmId != id else { return }
            self.activeAlarmId = id
        }
    }

    // =========================================================================
    // MARK: - Private: force-quit / memory-pressure recovery
    // =========================================================================

    /// On launch, if `kAlarmInProgress` is still set the process was killed while
    /// an alarm was ringing (force-quit, memory pressure, or rare OS termination).
    ///
    /// Recovery window: if the alarm started **within the last 15 minutes** we
    /// re-show the ring screen so the alarm continues.  Outside that window we
    /// record a failure (the user was asleep for too long to reasonably re-ring).
    private func checkForAbortedAlarm() {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: PunishmentEngine.kAlarmInProgress) else { return }

        let startTime  = ud.object(forKey: PunishmentEngine.kAlarmStartTimeKey) as? Date
        let alarmIdStr = ud.string(forKey: PunishmentEngine.kAlarmIdKey)

        // Clear flags immediately to prevent re-triggering on the next launch
        ud.removeObject(forKey: PunishmentEngine.kAlarmInProgress)
        ud.removeObject(forKey: PunishmentEngine.kAlarmIdKey)
        ud.removeObject(forKey: PunishmentEngine.kAlarmStartTimeKey)

        // End any stale Live Activity
        LiveActivityManager.shared.endActivity()

        let recoveryWindowSeconds: TimeInterval = 15 * 60   // 15 minutes

        if let startTime,
           let alarmIdStr,
           let alarmId = UUID(uuidString: alarmIdStr),
           Date().timeIntervalSince(startTime) < recoveryWindowSeconds,
           AlarmManager.shared.alarms.contains(where: { $0.id == alarmId }) {
            // Alarm is still current — re-activate the ring screen
            print("[AppCoordinator] Force-quit recovery: re-ringing alarm \(alarmIdStr)")
            DispatchQueue.main.async {
                self.activeAlarmId = alarmId
            }
        } else {
            // Alarm is too old or alarm was deleted — record failure
            StreakManager.shared.recordFailure()
        }
    }

    // =========================================================================
    // MARK: - Private: pending-alarm-on-launch
    // =========================================================================

    /// On launch, scan delivered notifications for any alarm-related notice.
    /// Covers three cases:
    /// 1. App was killed; user hasn't tapped the notification yet.
    /// 2. App was backgrounded and missed the `willPresent` callback.
    /// 3. Any burst or nag notification is still in the Notification Centre.
    ///    (All carry `alarmId` — added in the last fix session.)
    private func checkPendingAlarmOnLaunch() {
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            guard let self,
                  let match = notifications.first(where: {
                      $0.request.content.userInfo["alarmId"] != nil
                  }) else { return }
            self.handleAlarmNotification(
                match.request.content.userInfo,
                notificationId: match.request.identifier
            )
        }
    }

    // =========================================================================
    // MARK: - Private: foreground re-check
    // =========================================================================

    /// Called every time the app transitions to active (foreground).
    ///
    /// This is the critical path for the scenario:
    ///   1. Alarm fires → notifications appear on lock screen
    ///   2. User dismisses the lock screen / opens the app switcher / taps
    ///      the app icon — but does NOT tap the notification
    ///   3. App becomes foreground; neither `didReceive` nor the cold-launch
    ///      `checkPendingAlarmOnLaunch` fires at this point
    ///   4. ← This method fills that gap
    ///
    /// It scans `getDeliveredNotifications` for any un-dismissed alarm
    /// notification and routes it through the normal alarm handler, which
    /// presents the ring screen and starts the burst chain.
    @objc private func handleAppDidBecomeActive() {
        // If the ring screen is already showing there is nothing to do.
        guard activeAlarmId == nil else { return }

        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] delivered in
            guard let self else { return }

            // ── Path A: a notification was already delivered ──────────────────
            // Prefer the most recent alarm notification so we always surface
            // the right alarm when multiple are pending (edge case).
            if let match = delivered.first(where: {
                $0.request.content.userInfo["alarmId"] != nil
            }) {
                print("[AppCoordinator] App became active — found unhandled alarm " +
                      "notification '\(match.request.identifier)', presenting ring screen.")
                self.handleAlarmNotification(
                    match.request.content.userInfo,
                    notificationId: match.request.identifier
                )
                return
            }

            // ── Path B: no notification delivered yet (alarm fired < 1s ago, ─
            // ──          or notification center was cleared by the user)       ─
            // Fall back to checking whether any enabled alarm's fire time has
            // passed within the last 15 minutes.  This handles the case where
            // the user opens the app exactly as the alarm fires (race) or after
            // swiping away all notifications.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.checkAlarmTimePassedFallback()
            }
        }
    }

    /// Scans `AlarmManager.alarms` for any enabled alarm whose scheduled fire
    /// time fell within the last 15 minutes.  If found, activates the ring screen.
    ///
    /// This is a last-resort fallback; normally `getDeliveredNotifications` will
    /// find the alarm notification before this code runs.
    private func checkAlarmTimePassedFallback() {
        let now      = Date()
        let cal      = Calendar.current
        let window   = TimeInterval(15 * 60)   // 15-minute look-back

        for alarm in AlarmManager.shared.alarms where alarm.isEnabled {
            // Build today's (or yesterday's for overnight window) fire date
            var fireComps        = cal.dateComponents([.hour, .minute], from: alarm.time)
            fireComps.second     = 0

            // Try today
            if var todayComps = Optional(cal.dateComponents([.year, .month, .day], from: now)) {
                todayComps.hour   = fireComps.hour
                todayComps.minute = fireComps.minute
                todayComps.second = 0

                if let candidate = cal.date(from: todayComps) {
                    let elapsed = now.timeIntervalSince(candidate)
                    if elapsed >= 0 && elapsed <= window {
                        // Verify the alarm actually fires on this weekday
                        let weekday = cal.component(.weekday, from: candidate)
                        let fires   = alarm.repeatPattern == .once
                                   || alarm.activeDays.contains(weekday)
                        if fires {
                            print("[AppCoordinator] Fallback: alarm \(alarm.id) " +
                                  "fired \(Int(elapsed))s ago — presenting ring screen.")
                            activateAlarm(id: alarm.id)
                            return
                        }
                    }
                }
            }
        }
    }
}
