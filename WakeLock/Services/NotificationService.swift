import Foundation
import UserNotifications

/// Schedules and cancels local alarm notifications.
///
/// ## Sound strategy
/// alarm.caf is a 27-second urgent two-tone beeping pattern (A5/E6, 300ms on/120ms off).
/// iOS plays it once per notification delivery — longer than the default "ding".
///
/// ## Burst notifications  (app NOT open / process killed)
/// 15 follow-up notifications spaced 20 seconds apart (≈ 5 minutes total).
/// Every burst carries the alarmId so tapping any of them brings up the ring screen.
/// Cancelled the moment the alarm is dismissed via QR.
///
/// ## QR-nag notifications  (app IS open, ring screen showing)
/// 12 notifications spaced 30 seconds apart (≈ 6 minutes total).
/// Shown as banners over the ring screen via `willPresent([.sound, .banner])`.
/// Message nudges the user to scan the QR code.
/// Cancelled the moment the alarm is dismissed via QR.
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    // MARK: - Constants

    /// Sound file used for every alarm-related notification.
    static let alarmSoundName = UNNotificationSoundName("alarm.caf")

    private static let burstCount: Int        = 15     // 15 × 20 s ≈ 5 min
    private static let burstInterval: Double  = 20.0

    private static let nagCount: Int          = 12     // 12 × 30 s ≈ 6 min
    private static let nagInterval: Double    = 30.0

    // MARK: - Permission

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        ) { granted, error in
            if let error { print("[NotificationService] Auth error: \(error)") }
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func checkPermission(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Primary schedule

    func schedule(_ alarm: Alarm) {
        guard alarm.isEnabled else { return }
        cancel(alarm)

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let hasCritical = settings.criticalAlertSetting == .enabled
            let content = self.buildContent(for: alarm, hasCritical: hasCritical)

            if alarm.repeatPattern == .once {
                let trigger = self.calendarTrigger(for: alarm.time, weekday: nil, repeats: false)
                self.addRequest(id: alarm.id.uuidString, content: content, trigger: trigger)
            } else {
                for day in alarm.activeDays {
                    let trigger = self.calendarTrigger(for: alarm.time, weekday: day, repeats: true)
                    self.addRequest(id: "\(alarm.id.uuidString)-\(day)", content: content, trigger: trigger)
                }
            }
        }
    }

    func cancel(_ alarm: Alarm) {
        var ids = [alarm.id.uuidString]
        for day in 1...7 { ids.append("\(alarm.id.uuidString)-\(day)") }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        cancelBurst(alarmIdString: alarm.id.uuidString)
        cancelQRNag(alarmIdString: alarm.id.uuidString)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Burst notifications  (simulated looping when app is NOT running)

    /// Schedule `burstCount` follow-up notifications spaced `burstInterval` seconds apart.
    ///
    /// - Every burst carries the `alarmId` so tapping any banner — even if the
    ///   original notification was swiped away — will open the ring screen.
    /// - Call this the instant the first notification fires (from AppCoordinator).
    ///   Do NOT call again if the alarm is already active in-app (ring screen showing).
    func scheduleBurst(alarmIdString: String, label: String) {
        cancelBurst(alarmIdString: alarmIdString)

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let hasCritical = settings.criticalAlertSetting == .enabled
            let content = self.buildBurstContent(
                alarmIdString: alarmIdString,
                label: label,
                hasCritical: hasCritical
            )

            for i in 1...NotificationService.burstCount {
                let delay = Double(i) * NotificationService.burstInterval
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                self.addRequest(id: "\(alarmIdString)-burst-\(i)", content: content, trigger: trigger)
            }
        }
    }

    func cancelBurst(alarmIdString: String) {
        let ids = (1...NotificationService.burstCount).map { "\(alarmIdString)-burst-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - QR-nag notifications  (ring screen showing, user hasn't scanned yet)

    /// Schedule periodic "scan your QR code!" banners that fire while the ring
    /// screen is visible.  iOS delivers these as `willPresent` callbacks and we
    /// forward them with `[.sound, .banner]` so the user hears a fresh sound and
    /// sees a banner over the ring screen every ~30 seconds.
    ///
    /// Call from `AlarmRingViewModel.init()` after `PunishmentEngine.start()`.
    func scheduleQRNag(alarmIdString: String, label: String) {
        cancelQRNag(alarmIdString: alarmIdString)

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let hasCritical = settings.criticalAlertSetting == .enabled
            let content = self.buildNagContent(
                alarmIdString: alarmIdString,
                label: label,
                hasCritical: hasCritical
            )

            for i in 1...NotificationService.nagCount {
                let delay = Double(i) * NotificationService.nagInterval
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                self.addRequest(id: "\(alarmIdString)-nag-\(i)", content: content, trigger: trigger)
            }
        }
    }

    /// Cancel all pending QR-nag notifications.  Call from `completeDismissal()`.
    func cancelQRNag(alarmIdString: String) {
        let ids = (1...NotificationService.nagCount).map { "\(alarmIdString)-nag-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Content builders

    private func buildContent(for alarm: Alarm, hasCritical: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title              = "⏰ Wake Up!"
        content.body               = alarm.label.isEmpty ? "Time to get up!" : alarm.label
        content.categoryIdentifier = "ALARM"
        content.userInfo           = ["alarmId": alarm.id.uuidString]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func buildBurstContent(
        alarmIdString: String,
        label: String,
        hasCritical: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title              = "⏰ Still ringing!"
        content.body               = label.isEmpty ? "Get up! Tap to open the alarm." : "\(label) — tap to dismiss"
        content.categoryIdentifier = "ALARM"
        // KEY FIX: include alarmId so tapping ANY burst notification opens the ring screen,
        // even when the original notification was swiped away and the process was killed.
        content.userInfo           = ["alarmId": alarmIdString]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func buildNagContent(
        alarmIdString: String,
        label: String,
        hasCritical: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title              = "📱 Scan QR to stop alarm!"
        content.body               = "Open WakeLock and scan your QR code to dismiss."
        content.categoryIdentifier = "ALARM"
        content.userInfo           = ["alarmId": alarmIdString]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func applySound(to content: UNMutableNotificationContent, hasCritical: Bool) {
        if hasCritical {
            content.interruptionLevel = .critical
            content.sound = .criticalSoundNamed(NotificationService.alarmSoundName, withAudioVolume: 1.0)
        } else {
            content.interruptionLevel = .timeSensitive
            content.sound = .init(named: NotificationService.alarmSoundName)
        }
    }

    // MARK: - Helpers

    private func calendarTrigger(
        for date: Date,
        weekday: Int?,
        repeats: Bool
    ) -> UNCalendarNotificationTrigger {
        var comps: DateComponents
        if let weekday {
            comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            comps.weekday = weekday
        } else {
            comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
    }

    private func addRequest(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NotificationService] Schedule error (\(id)): \(error)") }
        }
    }
}
