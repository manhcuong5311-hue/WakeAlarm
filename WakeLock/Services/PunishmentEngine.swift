import Foundation
import Combine

/// The three escalation phases of the alarm
enum PunishmentPhase: Int {
    case phase1 = 1   // 0–30 s  — loud audio + haptic phase 1
    case phase2 = 2   // 30–60 s — ramped audio + haptic phase 2 + red flash
    case phase3 = 3   // 60 s+   — max everything + haptic phase 3 + urgent message
}

/// Drives the timed escalation system when the alarm fires.
/// Publishes phase changes that the ring UI observes and also pushes
/// Live Activity updates on phase transitions.
final class PunishmentEngine: ObservableObject {

    static let shared = PunishmentEngine()
    private init() {}

    // MARK: - UserDefaults keys

    static let kAlarmInProgress   = "wakelock.alarmInProgress"
    static let kAlarmIdKey        = "wakelock.alarmId"
    static let kAlarmStartTimeKey = "wakelock.alarmStartTime"

    // MARK: - Published state

    @Published private(set) var phase:          PunishmentPhase = .phase1
    @Published private(set) var elapsedSeconds: Int             = 0
    @Published private(set) var isRunning:      Bool            = false

    private var timer: AnyCancellable?

    // MARK: - Control

    func start(alarmId: UUID) {
        guard !isRunning else { return }
        isRunning      = true
        elapsedSeconds = 0
        phase          = .phase1

        let ud = UserDefaults.standard
        ud.set(true,              forKey: PunishmentEngine.kAlarmInProgress)
        ud.set(alarmId.uuidString, forKey: PunishmentEngine.kAlarmIdKey)
        ud.set(Date(),            forKey: PunishmentEngine.kAlarmStartTimeKey)

        // Start audio AND haptics immediately at phase 1
        AudioManager.shared.startAlarm()
        HapticsManager.shared.startPhase1()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    /// Called when the app returns to the foreground (`.active` scenePhase).
    /// Restarts audio and haptics if they were paused by the OS.
    func restoreIfNeeded() {
        guard isRunning else { return }
        AudioManager.shared.ensurePlaying()
        HapticsManager.shared.ensureRunning()
    }

    func stop() {
        timer?.cancel()
        timer     = nil
        isRunning = false

        let ud = UserDefaults.standard
        ud.removeObject(forKey: PunishmentEngine.kAlarmInProgress)
        ud.removeObject(forKey: PunishmentEngine.kAlarmIdKey)
        ud.removeObject(forKey: PunishmentEngine.kAlarmStartTimeKey)

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
            HapticsManager.shared.startPhase2()
            LiveActivityManager.shared.update(elapsedSeconds: 30, escalationLevel: 2)

        case 60:
            phase = .phase3
            AudioManager.shared.startAggressiveLayer()
            HapticsManager.shared.startPhase3()
            LiveActivityManager.shared.update(elapsedSeconds: 60, escalationLevel: 3)

        default: break
        }
    }
}
