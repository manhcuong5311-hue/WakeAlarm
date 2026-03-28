import Foundation
import Combine
import UserNotifications

final class HomeViewModel: ObservableObject {

    @Published var alarms: [Alarm] = []
    @Published var streak: StreakData = StreakData()
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var showCreateAlarm = false
    @Published var showQRSetup = false
    @Published var showPremiumSheet = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Mirror published values from singleton managers
        AlarmManager.shared.$alarms
            .map { alarms in
                alarms.sorted { a, b in
                    let cal = Calendar.current
                    let aH = cal.component(.hour,   from: a.time) * 60
                             + cal.component(.minute, from: a.time)
                    let bH = cal.component(.hour,   from: b.time) * 60
                             + cal.component(.minute, from: b.time)
                    return aH < bH
                }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$alarms)

        StreakManager.shared.$data
            .receive(on: DispatchQueue.main)
            .assign(to: &$streak)

        checkNotificationPermission()
    }

    // MARK: - Actions

    func toggleAlarm(_ alarm: Alarm) {
        AlarmManager.shared.toggle(alarm)
    }

    func deleteAlarm(_ alarm: Alarm) {
        AlarmManager.shared.delete(alarm)
    }

    func deleteAlarms(at offsets: IndexSet) {
        offsets.forEach { deleteAlarm(alarms[$0]) }
    }

    func tapCreateAlarm() {
        // Block alarm creation until at least one QR is registered
        guard QRManager.shared.hasQR else {
            showQRSetup = true
            return
        }
        // Free tier: max 2 alarms
        guard AlarmManager.shared.canAddAlarm else {
            showPremiumSheet = true
            return
        }
        showCreateAlarm = true
    }

    // MARK: - Permissions

    func requestNotificationPermission() {
        NotificationService.shared.requestPermission { [weak self] granted in
            self?.notificationStatus = granted ? .authorized : .denied
        }
    }

    func checkNotificationPermission() {
        NotificationService.shared.checkPermission { [weak self] status in
            self?.notificationStatus = status
        }
    }
}
