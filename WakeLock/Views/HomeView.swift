import SwiftUI

struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var editingAlarm: Alarm? = nil
    @State private var showSettings = false
    @State private var headerAppear = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Layout.sectionSpacing) {

                        // Custom header
                        headerSection
                            .padding(.horizontal, DS.Layout.screenPadding)
                            .padding(.top, 8)

                        // Notification warning
                        if vm.notificationStatus == .denied {
                            notificationBanner
                                .padding(.horizontal, DS.Layout.screenPadding)
                        }

                        // Streak card
                        StreakBannerView()
                            .padding(.horizontal, DS.Layout.screenPadding)

                        // QR setup nudge
                        if !QRManager.shared.hasQR {
                            qrNudgeBanner
                                .padding(.horizontal, DS.Layout.screenPadding)
                        }

                        // Alarms
                        if vm.alarms.isEmpty {
                            EmptyAlarmsView { vm.tapCreateAlarm() }
                                .padding(.top, 24)
                        } else {
                            alarmsSection
                        }

                        Spacer().frame(height: 110)
                    }
                }

                // Floating action button
                addButton
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showCreateAlarm) { CreateAlarmView() }
        .sheet(isPresented: $vm.showQRSetup)     { QRSetupView() }
        .sheet(item: $editingAlarm)              { CreateAlarmView(editing: $0) }
        .sheet(isPresented: $showSettings)       { SettingsView() }
        .onAppear {
            vm.checkNotificationPermission()
            if vm.notificationStatus == .notDetermined {
                vm.requestNotificationPermission()
            }
            withAnimation(DS.Animation.spring.delay(0.05)) { headerAppear = true }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(DS.Font.greeting)
                    .foregroundStyle(.primary)
                Text(formattedDate)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.label2)
            }

            Spacer()

            // Settings button
            Button {
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.appSurface)
                        .frame(width: 40, height: 40)
                        .shadow(color: DS.Shadow.card.color, radius: 8, y: 3)
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(PressEffectButtonStyle())
        }
        .opacity(headerAppear ? 1 : 0)
        .offset(y: headerAppear ? 0 : -8)
        .animation(DS.Animation.spring.delay(0.05), value: headerAppear)
    }

    // MARK: - Banners

    private var notificationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(DS.Color.danger)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Notifications off")
                    .font(DS.Font.captionBold)
                    .foregroundStyle(.primary)
                Text("Alarms won't fire without permission.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.label2)
            }
            Spacer()
            Button("Enable") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(DS.Font.captionBold)
            .foregroundStyle(DS.Color.accent)
        }
        .padding(14)
        .background(DS.Color.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Color.danger.opacity(0.2), lineWidth: 1)
        )
    }

    private var qrNudgeBanner: some View {
        Button { vm.showQRSetup = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(DS.Color.success.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.Color.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up QR code")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(.primary)
                    Text("Required to create alarms")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.label2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.label3)
            }
            .padding(DS.Layout.cardPadding)
            .cardStyle()
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    // MARK: - Alarms

    private var alarmsSection: some View {
        VStack(spacing: 0) {
            SectionHeaderView(title: "Alarms", trailing: "Edit") {}
                .padding(.bottom, 10)

            VStack(spacing: DS.Layout.itemSpacing) {
                ForEach(vm.alarms) { alarm in
                    AlarmCardView(
                        alarm:    alarm,
                        onToggle: { vm.toggleAlarm(alarm) },
                        onDelete: { vm.deleteAlarm(alarm) },
                        onEdit:   { editingAlarm = alarm }
                    )
                    .padding(.horizontal, DS.Layout.screenPadding)
                }
            }
        }
    }

    // MARK: - FAB

    private var addButton: some View {
        Button { vm.tapCreateAlarm() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("New Alarm")
                    .font(DS.Font.bodyBold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(height: DS.Layout.buttonHeight)
            .background(DS.Gradient.accent)
            .clipShape(Capsule())
            .shadow(color: DS.Shadow.button.color, radius: DS.Shadow.button.radius, y: DS.Shadow.button.y)
        }
        .buttonStyle(PressEffectButtonStyle())
        .padding(.bottom, 36)
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

#Preview {
    HomeView()
}
