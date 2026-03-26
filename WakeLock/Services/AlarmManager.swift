import Foundation
import Combine

private let kAlarmsKey = "wakelock.alarms"

/// Central store for all alarms.
/// Persists to UserDefaults, keeps notifications in sync, and manages the
/// AudioManager keepalive session so background alarm delivery works without
/// the critical-alerts entitlement.
final class AlarmManager: ObservableObject {

    static let shared = AlarmManager()
    private init() {
        load()
        syncKeepalive()
    }

    @Published private(set) var alarms: [Alarm] = []

    /// Free tier: max 2 alarms. Premium users have no limit.
    var canAddAlarm: Bool {
        PremiumManager.shared.isPremium || alarms.count < 2
    }

    // MARK: - CRUD

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
        if alarm.isEnabled { NotificationService.shared.schedule(alarm) }
        save()
        syncKeepalive()
    }

    func update(_ alarm: Alarm) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        NotificationService.shared.cancel(alarms[idx])
        alarms[idx] = alarm
        if alarm.isEnabled { NotificationService.shared.schedule(alarm) }
        save()
        syncKeepalive()
    }

    func delete(_ alarm: Alarm) {
        NotificationService.shared.cancel(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
        syncKeepalive()
    }

    func toggle(_ alarm: Alarm) {
        var updated = alarm
        updated.isEnabled.toggle()
        update(updated)
    }

    // MARK: - Keepalive management

    /// Start a silent background audio loop when any alarm is enabled,
    /// stop it when none are.  This keeps the process in the "background audio"
    /// state so the AVAudioPlayer can fire on time without a cold start.
    private func syncKeepalive() {
        if alarms.contains(where: { $0.isEnabled }) {
            AudioManager.shared.startKeepalive()
        } else {
            AudioManager.shared.stopKeepalive()
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: kAlarmsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: kAlarmsKey),
              let decoded = try? JSONDecoder().decode([Alarm].self, from: data) else { return }
        alarms = decoded
    }
}
