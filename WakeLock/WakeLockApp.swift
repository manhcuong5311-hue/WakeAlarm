import SwiftUI

@main
struct WakeLockApp: App {

    @StateObject private var coordinator = AppCoordinator.shared

    init() {
        _ = AppCoordinator.shared   // register notification delegate early
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                // Handle "wakelock://ring/<uuid>" deep links from the Live Activity
                .onOpenURL { coordinator.handleOpenURL($0) }
        }
    }
}

// MARK: - RootView

/// Sits above HomeView and presents the ring screen as a fullScreenCover
/// whenever AppCoordinator sets activeAlarmId.
struct RootView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        HomeView()
            .fullScreenCover(item: alarmTriggerBinding) { trigger in
                ringScreen(for: trigger)
            }
    }

    private var alarmTriggerBinding: Binding<AlarmTrigger?> {
        Binding(
            get:  { coordinator.activeAlarmId.map { AlarmTrigger(id: $0) } },
            set:  { if $0 == nil { coordinator.dismissRingScreen() } }
        )
    }

    @ViewBuilder
    private func ringScreen(for trigger: AlarmTrigger) -> some View {
        if let alarm = AlarmManager.shared.alarms.first(where: { $0.id == trigger.id }) {
            RingScreenHost(alarm: alarm)
        } else {
            // Alarm was deleted while ring screen was pending
            Color.black.ignoresSafeArea()
                .onAppear { coordinator.dismissRingScreen() }
        }
    }
}

// MARK: - RingScreenHost

/// Hosts AlarmRingView. Recovers audio/haptics when the app returns to the
/// foreground after an interruption (lock screen, phone call, etc.).
struct RingScreenHost: View {

    let alarm: Alarm
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var ringVM: AlarmRingViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(alarm: Alarm) {
        self.alarm = alarm
        _ringVM = StateObject(wrappedValue: AlarmRingViewModel(alarm: alarm))
    }

    var body: some View {
        AlarmRingView(vm: ringVM)
            .onChange(of: ringVM.isDismissed) { _, dismissed in
                if dismissed {
                    coordinator.dismissRingScreen()
                    // If a second alarm fired while this ring screen was visible
                    // (its notification was held back to avoid switching screens),
                    // present its ring screen now.  Small delay lets SwiftUI finish
                    // tearing down the current fullScreenCover first.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        coordinator.checkForNextAlarm()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Recovery: when the app returns to foreground, ensure audio and
                // haptics are still running (they may have been paused by the OS
                // during a phone call, lock screen, or media interruption).
                guard phase == .active, !ringVM.isDismissed else { return }
                PunishmentEngine.shared.restoreIfNeeded()
            }
    }
}

// MARK: - AlarmTrigger

/// Lightweight Identifiable wrapper so fullScreenCover can be item-driven.
struct AlarmTrigger: Identifiable, Equatable {
    let id: UUID
}
