import SwiftUI

struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var qrManager = QRManager.shared
    @State private var editingAlarm: Alarm?  = nil
    @State private var showSettings          = false
    @State private var showQRPicker          = false   // quick primary-picker sheet
    @State private var headerAppear          = false

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

                        // QR status / setup nudge
                        if !qrManager.hasQR {
                            qrNudgeBanner
                                .padding(.horizontal, DS.Layout.screenPadding)
                        } else {
                            qrStatusCard
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
        .sheet(isPresented: $vm.showCreateAlarm)  { CreateAlarmView() }
        .sheet(isPresented: $vm.showQRSetup)      { QRSetupView() }
        .sheet(item: $editingAlarm)               { CreateAlarmView(editing: $0) }
        .sheet(isPresented: $showSettings)        { SettingsView() }
        .sheet(isPresented: $vm.showPremiumSheet) { PremiumPaywallView() }
        .sheet(isPresented: $showQRPicker)        { QRPrimaryPickerSheet() }
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

    private var qrStatusCard: some View {
        let primary = qrManager.entries.first(where: { $0.isPrimary })
        let count   = qrManager.entries.count

        return VStack(spacing: 0) {
            // ── Primary code row ──────────────────────────────────────────────
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(DS.Color.success.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: primary?.typeIcon ?? "qrcode")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.Color.success)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primary?.label ?? "No Primary")
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Type badge  (e.g. "QR Code")
                        if let primary {
                            Text(primary.typeDisplayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Color.success)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DS.Color.success.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }

                    // Shape hint + secondary count
                    HStack(spacing: 4) {
                        if let primary {
                            // Shape badge  (Square / Linear / Circular …)
                            Text(primary.shapeHint)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Color.label3)
                        }
                        if count > 1 {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.label3)
                            Text("\(count) codes saved")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.label3)
                        }
                    }
                }

                Spacer(minLength: 4)

                // ── Action buttons ────────────────────────────────────────────
                HStack(spacing: 8) {
                    // Quick primary-picker — only useful when there is more than 1 QR
                    if count > 1 {
                        Button {
                            showQRPicker = true
                        } label: {
                            Text("Change")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(DS.Color.accent.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showSettings = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Color.label3)
                            .frame(width: 28, height: 28)
                            .background(Color.appSurface.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Layout.cardPadding)
        }
        .cardStyle()
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
            SectionHeaderView(
                title: "Alarms",
                trailing: !PremiumManager.shared.isPremium ? "Free: \(vm.alarms.count)/2" : nil,
                trailingAction: nil
            )
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

// MARK: - QR Primary Picker Sheet

/// A compact sheet that lists every saved QR/barcode and lets the user
/// tap one to make it the primary code used for alarm dismissal.
struct QRPrimaryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var qrManager = QRManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if qrManager.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 40))
                            .foregroundStyle(DS.Color.label3)
                        Text("No QR codes saved yet")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.label2)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(qrManager.entries.enumerated()), id: \.element.id) { idx, entry in
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(DS.Animation.smooth) {
                                            qrManager.setPrimary(entry)
                                        }
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            // Icon
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(entry.isPrimary
                                                          ? DS.Color.success.opacity(0.15)
                                                          : Color.appSurface)
                                                    .frame(width: 44, height: 44)
                                                Image(systemName: entry.typeIcon)
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundStyle(entry.isPrimary
                                                                     ? DS.Color.success
                                                                     : DS.Color.label2)
                                            }

                                            // Info
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(entry.label)
                                                    .font(DS.Font.bodyBold)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)

                                                HStack(spacing: 5) {
                                                    // Shape hint
                                                    Text(entry.shapeHint)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(DS.Color.label3)

                                                    Text("·")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(DS.Color.label3)

                                                    // Full type name
                                                    Text(entry.typeDisplayName)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(DS.Color.label3)
                                                }

                                                // Value preview
                                                Text(String(entry.value.prefix(30))
                                                     + (entry.value.count > 30 ? "…" : ""))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(DS.Color.label3.opacity(0.7))
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            // Primary indicator / select
                                            if entry.isPrimary {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(DS.Color.success)
                                            } else {
                                                Image(systemName: "circle")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(DS.Color.label3)
                                            }
                                        }
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, DS.Layout.cardPadding)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressEffectButtonStyle())

                                    if idx < qrManager.entries.count - 1 {
                                        Divider()
                                            .padding(.leading, DS.Layout.cardPadding + 58)
                                            .opacity(0.35)
                                    }
                                }
                            }
                        }
                        .cardStyle()
                        .padding(.horizontal, DS.Layout.screenPadding)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Set Primary Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
