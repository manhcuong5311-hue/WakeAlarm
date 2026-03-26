import Foundation
import Combine

/// The three escalation phases of the alarm
enum PunishmentPhase: Int {
    case phase1 = 1   // 0–30s  – normal loud
    case phase2 = 2   // 30–60s – ramp volume + haptics + red flash
    case phase3 = 3   // 60s+   – max everything + urgent message
}

/// Drives the timed escalation system when the alarm fires.
/// Publishes phase changes that the ring UI observes and also pushes
/// Live Activity updates on phase transitions.
final class PunishmentEngine: ObservableObject {

    static let shared = PunishmentEngine()
    private init() {}

    /// UserDefaults key set while an alarm is actively ringing.
    /// Lets us detect force-quit / crash on the next launch.
    static let kAlarmInProgress = "wakelock.alarmInProgress"

    @Published private(set) var phase: PunishmentPhase = .phase1
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false

    private var timer: AnyCancellable?

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        isRunning      = true
        elapsedSeconds = 0
        phase          = .phase1

        // Persist flag — cleared in stop() — for force-quit detection
        UserDefaults.standard.set(true, forKey: PunishmentEngine.kAlarmInProgress)

        AudioManager.shared.startAlarm()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    /// Called when the app returns to the foreground (.active scenePhase).
    /// Restarts any audio or haptic player that the OS silenced or paused.
    func restoreIfNeeded() {
        guard isRunning else { return }
        AudioManager.shared.ensurePlaying()
        // Re-arm haptics for the current phase
        switch phase {
        case .phase1: break          // haptics don't start until phase 2
        case .phase2: HapticsManager.shared.ensureRunning(intense: false)
        case .phase3: HapticsManager.shared.ensureRunning(intense: true)
        }
    }

    func stop() {
        timer?.cancel()
        timer   = nil
        isRunning = false

        // Clear the force-quit flag (alarm ended normally)
        UserDefaults.standard.removeObject(forKey: PunishmentEngine.kAlarmInProgress)

        AudioManager.shared.stopAlarm()
        HapticsManager.shared.stop()
    }

    // MARK: - Escalation tick

    private func tick() {
        elapsedSeconds += 1

        switch elapsedSeconds {
        case 30:
            phase = .phase2
            AudioManager.shared.rampToMax()
            HapticsManager.shared.startContinuous()
            LiveActivityManager.shared.update(elapsedSeconds: 30, escalationLevel: 2)

        case 60:
            phase = .phase3
            AudioManager.shared.startAggressiveLayer()
            HapticsManager.shared.startIntense()
            LiveActivityManager.shared.update(elapsedSeconds: 60, escalationLevel: 3)

        default: break
        }
    }
}
