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
