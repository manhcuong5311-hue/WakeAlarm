import Foundation
import Combine
import LocalAuthentication

final class AlarmRingViewModel: ObservableObject {

    let alarm: Alarm

    @Published var isDismissed: Bool = false
    @Published var showQRScanner: Bool = false
    @Published var biometricError: String? = nil
    @Published var biometricAvailable: Bool = false

    init(alarm: Alarm) {
        self.alarm = alarm
        checkBiometrics()
        LiveActivityManager.shared.startActivity(for: alarm)
        PunishmentEngine.shared.start()

        // Schedule QR-nag notifications: fires every 30 s as long as the ring
        // screen is showing.  Shown as banners + sound via willPresent so the
        // user keeps hearing the alarm even if they switch apps.
        // Also acts as a persistent reminder: "Scan QR to dismiss!"
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

        // Cancel ALL pending alarm notifications so nothing fires after dismiss.
        NotificationService.shared.cancelBurst(alarmIdString: alarm.id.uuidString)
        NotificationService.shared.cancelQRNag(alarmIdString: alarm.id.uuidString)

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
        if !isDismissed && PunishmentEngine.shared.isRunning {
            PunishmentEngine.shared.stop()
            LiveActivityManager.shared.endActivity()
            NotificationService.shared.cancelBurst(alarmIdString: alarm.id.uuidString)
            NotificationService.shared.cancelQRNag(alarmIdString: alarm.id.uuidString)
            StreakManager.shared.recordFailure()
        }
    }
}
