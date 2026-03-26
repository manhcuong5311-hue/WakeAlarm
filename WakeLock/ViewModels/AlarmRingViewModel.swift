import Foundation
import Combine
import LocalAuthentication

final class AlarmRingViewModel: ObservableObject {

    let alarm: Alarm

    @Published var isDismissed:       Bool   = false
    @Published var showQRScanner:     Bool   = false
    @Published var biometricError:    String? = nil
    @Published var biometricAvailable: Bool  = false

    init(alarm: Alarm) {
        self.alarm = alarm
        checkBiometrics()
        LiveActivityManager.shared.startActivity(for: alarm)

        // Start the punishment engine — stores alarm ID + start time for
        // force-quit recovery so AppCoordinator can re-ring within 15 min.
        PunishmentEngine.shared.start(alarmId: alarm.id)

        // Schedule QR-nag notifications: fires every 30 s while the ring screen
        // is showing, displayed as banners + sound over the ring screen.
        // "Scan QR to stop alarm!" — ensures the user can't ignore it even if
        // they switch apps or the screen dims.
        NotificationService.shared.scheduleQRNag(
            alarmIdString: alarm.id.uuidString,
            label: alarm.label
        )
    }

    // MARK: - Dismissal paths

    func dismissViaQR() {
        showQRScanner = true
    }

    func dismissViaBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            biometricError = "Biometric authentication not available."
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Authenticate to dismiss your alarm"
        ) { [weak self] success, authError in
            DispatchQueue.main.async {
                if success { self?.completeDismissal() }
                else { self?.biometricError = authError?.localizedDescription ?? "Authentication failed." }
            }
        }
    }

    func onQRSuccess() { completeDismissal() }

    // MARK: - Private

    private func completeDismissal() {
        let elapsed = PunishmentEngine.shared.elapsedSeconds
        PunishmentEngine.shared.stop()
        LiveActivityManager.shared.endActivity()

        // Cancel every pending alarm notification — nothing should fire after dismiss
        NotificationService.shared.cancelBurst(alarmIdString: alarm.id.uuidString)
        NotificationService.shared.cancelQRNag(alarmIdString: alarm.id.uuidString)

        // For repeating alarms: the primary `UNCalendarNotificationTrigger(repeats: true)`
        // fires again automatically on the next occurrence, but the pre-emptive burst
        // notifications were consumed by this dismissal.  Re-call schedule() so a fresh
        // set of pre-emptive bursts is queued for the next occurrence.
        if alarm.repeatPattern != .once {
            NotificationService.shared.schedule(alarm)
        }

        if elapsed <= 300 { StreakManager.shared.recordSuccess() }
        else               { StreakManager.shared.recordFailure() }

        isDismissed = true
    }

    private func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        biometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    deinit {
        guard !isDismissed, PunishmentEngine.shared.isRunning else { return }

        // Guard against SwiftUI view-tree rebuilds where the old ViewModel is
        // deinited but the ring screen is immediately recreated with a new one.
        // In that case AppCoordinator still holds `activeAlarmId == alarm.id`, so
        // we should NOT stop the engine — the new ViewModel will keep it running.
        //
        // We use a tiny async dispatch so the new ViewModel's init() runs first
        // and updates AppCoordinator before we decide whether to stop.
        let alarmId    = alarm.id
        let alarmIdStr = alarm.id.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // If a new ring screen is already showing for the same alarm, bail out.
            guard AppCoordinator.shared.activeAlarmId != alarmId else { return }
            // If PunishmentEngine was restarted by the new ViewModel, bail out.
            guard PunishmentEngine.shared.isRunning else { return }

            PunishmentEngine.shared.stop()
            LiveActivityManager.shared.endActivity()
            NotificationService.shared.cancelBurst(alarmIdString: alarmIdStr)
            NotificationService.shared.cancelQRNag(alarmIdString: alarmIdStr)
            StreakManager.shared.recordFailure()
        }
    }
}
