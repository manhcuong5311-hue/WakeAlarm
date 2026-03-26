import Foundation
import UserNotifications

/// Schedules and cancels all WakeLock local notifications.
///
/// ## Notification types
///
/// | Type     | `notificationType` | When scheduled               | `alarmId`? |
/// |----------|--------------------|------------------------------|------------|
/// | Primary  | `"alarm"`          | Alarm creation / edit        | ✅          |
/// | Burst    | `"burst"`          | Moment first notification fires | ✅       |
/// | QR Nag   | `"nag"`            | Ring screen appears          | ✅          |
///
/// Every notification carries `alarmId` in `userInfo` so tapping any of them —
/// even after the original notification is swiped away and the process is killed —
/// cold-launches the app and presents the correct ring screen.
///
/// ## Burst chain  (app NOT running or process killed)
/// 15 × 20 s ≈ 5-minute window.  `AppCoordinator` extends this window infinitely
/// by rescheduling a fresh 15-burst batch each time a burst fires while the alarm
/// is still active (rolling chain).
///
/// ## QR-nag chain  (ring screen visible, user hasn't scanned yet)
/// 12 × 30 s ≈ 6-minute window of "Scan QR to stop!" banners shown over the ring
/// screen via `willPresent([.sound, .banner])`.
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    // MARK: - Constants

    static let alarmSoundName = UNNotificationSoundName("alarm.caf")

    private static let burstCount:    Int    = 30      // 30 × 15 s = 7.5-min aggressive window
    private static let burstInterval: Double = 15.0    // fire every 15 s

    /// Pre-emptive bursts are scheduled at alarm-creation time using exact
    /// `UNCalendarNotificationTrigger` dates so they fire even when the phone
    /// is sleeping and `willPresent`/`didReceive` are never called.
    private static let preemptiveBurstCount: Int = 20  // 20 × 15 s = 5-min guaranteed window

    private static let nagCount:    Int    = 12
    private static let nagInterval: Double = 30.0

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
            let content = self.buildPrimaryContent(for: alarm, hasCritical: hasCritical)

            if alarm.repeatPattern == .once {
                let trigger = self.calendarTrigger(for: alarm.time, weekday: nil, repeats: false)
                self.addRequest(id: alarm.id.uuidString, content: content, trigger: trigger)
            } else {
                for day in alarm.activeDays {
                    let trigger = self.calendarTrigger(for: alarm.time, weekday: day, repeats: true)
                    self.addRequest(id: "\(alarm.id.uuidString)-\(day)", content: content, trigger: trigger)
                }
            }

            // ── Pre-emptive burst chain ───────────────────────────────────────
            // Schedule burst notifications RIGHT NOW at exact calendar dates.
            // These fire even when the phone is sleeping and the app is never
            // launched — no willPresent / didReceive callback required.
            // This fixes the "only 1 notification when screen locked" bug.
            if let fireDate = self.nextFireDate(for: alarm) {
                self.schedulePreemptiveBursts(alarm: alarm, fireDate: fireDate, hasCritical: hasCritical)
            }
        }
    }

    /// Returns the next future date this alarm is scheduled to fire.
    /// Used to anchor pre-emptive burst timestamps.
    func nextFireDate(for alarm: Alarm) -> Date? {
        let now = Date()
        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute], from: alarm.time)
        guard let hour = timeComps.hour, let minute = timeComps.minute else { return nil }

        if alarm.repeatPattern == .once {
            return alarm.time > now ? alarm.time : nil
        }

        let days = alarm.activeDays
        guard !days.isEmpty else { return nil }

        for daysAhead in 0...7 {
            guard let candidate = cal.date(byAdding: .day, value: daysAhead, to: now) else { continue }
            let weekday = cal.component(.weekday, from: candidate)
            guard days.contains(weekday) else { continue }
            var comps        = cal.dateComponents([.year, .month, .day], from: candidate)
            comps.hour       = hour
            comps.minute     = minute
            comps.second     = 0
            guard let fireDate = cal.date(from: comps) else { continue }
            if fireDate > now { return fireDate }
        }
        return nil
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

    // MARK: - Burst chain  (process NOT running)

    /// Schedule `burstCount` follow-up notifications every `burstInterval` seconds.
    ///
    /// Each burst carries `alarmId` + `notificationType = "burst"` so:
    /// - Tapping any burst cold-launches the ring screen (fixed the "screen opens
    ///   but alarm disappears" bug where tapping a burst did nothing).
    /// - `AppCoordinator` detects the `"burst"` type and reschedules another batch,
    ///   creating an infinite rolling window until the alarm is dismissed via QR.
    ///
    /// Call this the moment the **first** alarm notification fires.
    /// Do **not** call again if `PunishmentEngine.isRunning` — the coordinator
    /// handles rescheduling automatically via the rolling-chain logic.
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

            // ── Aggressive burst window (first 7.5 min) ──────────────────────
            // 30 notifications at 15-second intervals — fires whether the app
            // is alive or completely killed.
            for i in 1...NotificationService.burstCount {
                let delay   = Double(i) * NotificationService.burstInterval
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                self.addRequest(id: "\(alarmIdString)-burst-\(i)", content: content, trigger: trigger)
            }

            // ── Infinite repeating fallback ───────────────────────────────────
            // After the burst window the OS keeps delivering this every 60 s
            // indefinitely — even with the app process fully dead — until
            // cancelBurst() removes it on QR-code dismissal.
            // iOS enforces a 60-second minimum for repeating triggers.
            let repeatTrigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 60, repeats: true
            )
            self.addRequest(
                id: "\(alarmIdString)-repeat",
                content: content,
                trigger: repeatTrigger
            )
        }
    }

    func cancelBurst(alarmIdString: String) {
        // Reactive bursts (scheduled while app is running)
        var ids = (1...NotificationService.burstCount).map { "\(alarmIdString)-burst-\($0)" }
        // Infinite repeating fallback trigger
        ids.append("\(alarmIdString)-repeat")
        // Pre-emptive bursts (scheduled at alarm-creation time, fire while sleeping)
        ids += (1...NotificationService.preemptiveBurstCount).map { "\(alarmIdString)-pburst-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Pre-emptive burst chain  (scheduled at alarm-creation time)

    /// Schedule `preemptiveBurstCount` burst notifications using exact
    /// `UNCalendarNotificationTrigger` dates anchored to `fireDate`.
    ///
    /// Unlike the reactive burst chain (which requires the app to receive a
    /// `willPresent` callback), these are queued by the OS scheduler and fire
    /// independently — even when the phone is locked, the process is killed, or
    /// the screen has been off for hours.
    ///
    /// IDs use the `-pburst-N` suffix so `cancelBurst()` can remove them on QR
    /// dismissal without touching unrelated notifications.
    private func schedulePreemptiveBursts(alarm: Alarm, fireDate: Date, hasCritical: Bool) {
        let content = buildBurstContent(
            alarmIdString: alarm.id.uuidString,
            label: alarm.label,
            hasCritical: hasCritical
        )
        let cal = Calendar.current

        for i in 1...NotificationService.preemptiveBurstCount {
            let delay = Double(i) * NotificationService.burstInterval
            guard let burstDate = cal.date(
                byAdding: .second,
                value: Int(delay),
                to: fireDate
            ) else { continue }

            let comps = cal.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: burstDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            addRequest(
                id: "\(alarm.id.uuidString)-pburst-\(i)",
                content: content,
                trigger: trigger
            )
        }

        print("[NotificationService] Pre-emptive bursts scheduled: " +
              "\(NotificationService.preemptiveBurstCount) × " +
              "\(Int(NotificationService.burstInterval))s from \(fireDate)")
    }

    // MARK: - QR-nag chain  (ring screen visible)

    /// Schedule "Scan QR to stop!" banners delivered while the ring screen is
    /// visible.  iOS fires them through `willPresent` so they appear as banners
    /// over the ring screen and play alarm.caf even while the app is foreground.
    ///
    /// Call from `AlarmRingViewModel.init()` immediately after `PunishmentEngine.start()`.
    func scheduleQRNag(alarmIdString: String, label: String) {
        cancelQRNag(alarmIdString: alarmIdString)

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let hasCritical = settings.criticalAlertSetting == .enabled
            let content = self.buildNagContent(
                alarmIdString: alarmIdString,
                hasCritical: hasCritical
            )
            for i in 1...NotificationService.nagCount {
                let delay   = Double(i) * NotificationService.nagInterval
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

    private func buildPrimaryContent(
        for alarm: Alarm,
        hasCritical: Bool
    ) -> UNMutableNotificationContent {
        let content                    = UNMutableNotificationContent()
        content.title                  = "⏰ Wake Up!"
        content.body                   = alarm.label.isEmpty ? "Time to get up!" : alarm.label
        content.categoryIdentifier     = "ALARM"
        content.userInfo               = [
            "alarmId":          alarm.id.uuidString,
            "notificationType": "alarm"
        ]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func buildBurstContent(
        alarmIdString: String,
        label: String,
        hasCritical: Bool
    ) -> UNMutableNotificationContent {
        let content                    = UNMutableNotificationContent()
        content.title                  = "⏰ Still ringing!"
        content.body                   = label.isEmpty
            ? "Get up! Tap to open the alarm."
            : "\(label) — tap to dismiss"
        content.categoryIdentifier     = "ALARM"
        // alarmId enables cold-launch ring screen; notificationType enables
        // AppCoordinator's rolling-chain rescheduling logic.
        content.userInfo               = [
            "alarmId":          alarmIdString,
            "notificationType": "burst"
        ]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func buildNagContent(
        alarmIdString: String,
        hasCritical: Bool
    ) -> UNMutableNotificationContent {
        let content                    = UNMutableNotificationContent()
        content.title                  = "📱 Scan QR to stop alarm!"
        content.body                   = "Open WakeLock and scan your QR code to dismiss."
        content.categoryIdentifier     = "ALARM"
        content.userInfo               = [
            "alarmId":          alarmIdString,
            "notificationType": "nag"
        ]
        applySound(to: content, hasCritical: hasCritical)
        return content
    }

    private func applySound(
        to content: UNMutableNotificationContent,
        hasCritical: Bool
    ) {
        if hasCritical {
            content.interruptionLevel = .critical
            content.sound = .criticalSoundNamed(
                NotificationService.alarmSoundName,
                withAudioVolume: 1.0
            )
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
            comps          = Calendar.current.dateComponents([.hour, .minute], from: date)
            comps.weekday  = weekday
        } else {
            comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
        }
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
    }

    private func addRequest(
        id: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger
    ) {
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                print("[NotificationService] Schedule error (\(id)): \(error)")
            }
        }
    }
}
