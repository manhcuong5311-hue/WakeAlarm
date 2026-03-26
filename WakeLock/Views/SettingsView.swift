import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var qrManager = QRManager.shared
    @ObservedObject private var streakManager = StreakManager.shared

    @State private var showAddQR = false
    @State private var showQRScanner = false
    @State private var newQRLabel = "Bathroom"
    @State private var pendingQRValue: String? = nil
    @State private var isPremium = UserDefaults.standard.bool(forKey: "wakelock.premium")
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Layout.sectionSpacing) {

                        // QR codes
                        qrSection
                        // Streak stats
                        streakSection
                        // Premium
                        premiumSection
                        // About
                        aboutSection

                        Spacer().frame(height: 40)
                    }
                    .padding(.top, DS.Layout.sectionSpacing)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
        .sheet(isPresented: $showAddQR) { addQRSheet }
        .onAppear { withAnimation(DS.Animation.spring.delay(0.05)) { appear = true } }
    }

    // MARK: - QR section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "QR Codes",
                              trailing: qrManager.canAddMore ? "Add" : nil,
                              trailingAction: { showAddQR = true })

            VStack(spacing: 0) {
                ForEach(Array(qrManager.entries.enumerated()), id: \.element.id) { idx, entry in
                    VStack(spacing: 0) {
                        qrEntryRow(entry)
                        if idx < qrManager.entries.count - 1 {
                            Divider().padding(.leading, 60).opacity(0.4)
                        }
                    }
                }

                if qrManager.entries.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode").font(.system(size: 28)).foregroundStyle(DS.Color.label3)
                            Text("No QR codes yet")
                                .font(DS.Font.caption).foregroundStyle(DS.Color.label3)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                }

                if qrManager.canAddMore {
                    if !qrManager.entries.isEmpty { Divider().padding(.leading, 60).opacity(0.4) }
                    Button { showAddQR = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.Color.accent)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("Add QR Code")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.accent)
                            Spacer()
                        }
                        .padding(DS.Layout.cardPadding)
                    }
                    .buttonStyle(PressEffectButtonStyle())
                } else if !isPremium {
                    Divider().padding(.leading, 60).opacity(0.4)
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Color.streak)
                        Text("Upgrade for multiple QR codes")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.label2)
                    }
                    .padding(DS.Layout.cardPadding)
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
        .scaleEffect(appear ? 1 : 0.97)
        .opacity(appear ? 1 : 0)
        .animation(DS.Animation.spring.delay(0.05), value: appear)
    }

    private func qrEntryRow(_ entry: QRCodeEntry) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.Color.success.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "qrcode")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.label).font(DS.Font.bodyBold)
                    if entry.isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(DS.Color.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Color.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(String(entry.value.prefix(28)) + (entry.value.count > 28 ? "…" : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.label3)
            }
            Spacer()
        }
        .padding(DS.Layout.cardPadding)
        .swipeActions(edge: .leading) {
            Button("Primary") { qrManager.setPrimary(entry) }
                .tint(DS.Color.success)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) { qrManager.delete(entry) }
        }
    }

    // MARK: - Streak section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Wake-up Streak")

            VStack(spacing: 0) {
                statRow(icon: "flame.fill", iconColor: DS.Color.streak,
                        title: "Current streak",
                        value: "\(streakManager.data.currentStreak) days",
                        valueColor: DS.Color.streak)
                Divider().padding(.leading, 60).opacity(0.4)
                statRow(icon: "trophy.fill", iconColor: Color(hex: "FFD700"),
                        title: "Longest streak",
                        value: "\(streakManager.data.longestStreak) days",
                        valueColor: Color(hex: "FFD700"))
                Divider().padding(.leading, 60).opacity(0.4)
                statRow(icon: "checkmark.circle.fill", iconColor: DS.Color.success,
                        title: "Total successes",
                        value: "\(streakManager.data.totalSuccesses)",
                        valueColor: DS.Color.success)
                if isPremium {
                    Divider().padding(.leading, 60).opacity(0.4)
                    statRow(icon: "snowflake", iconColor: DS.Color.accent,
                            title: "Streak freezes",
                            value: "\(streakManager.data.freezesRemaining) left",
                            valueColor: DS.Color.accent)
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
        .scaleEffect(appear ? 1 : 0.97)
        .opacity(appear ? 1 : 0)
        .animation(DS.Animation.spring.delay(0.09), value: appear)
    }

    private func statRow(icon: String, iconColor: Color, title: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(title).font(DS.Font.body)
            Spacer()
            Text(value)
                .font(DS.Font.bodyBold)
                .foregroundStyle(valueColor)
        }
        .padding(DS.Layout.cardPadding)
    }

    // MARK: - Premium section

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Premium")

            if isPremium {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.Gradient.accent)
                            .frame(width: 32, height: 32)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium Active").font(DS.Font.bodyBold)
                        Text("All features unlocked").font(DS.Font.caption).foregroundStyle(DS.Color.label2)
                    }
                    Spacer()
                }
                .padding(DS.Layout.cardPadding)
                .cardStyle()
                .padding(.horizontal, DS.Layout.screenPadding)
            } else {
                Button {
                    UserDefaults.standard.set(true, forKey: "wakelock.premium")
                    withAnimation(DS.Animation.spring) { isPremium = true }
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DS.Gradient.accent)
                                .frame(width: 40, height: 40)
                            Image(systemName: "star.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Unlock Premium").font(DS.Font.bodyBold)
                            Text("Multiple QR · Streak freeze · Analytics")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.label2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Color.label3)
                    }
                    .padding(DS.Layout.cardPadding)
                    .background(
                        ZStack {
                            Color.appSurface
                            LinearGradient(
                                colors: [DS.Color.accent.opacity(0.06), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous)
                            .stroke(DS.Color.accent.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)
                }
                .buttonStyle(PressEffectButtonStyle())
                .padding(.horizontal, DS.Layout.screenPadding)
            }
        }
        .scaleEffect(appear ? 1 : 0.97)
        .opacity(appear ? 1 : 0)
        .animation(DS.Animation.spring.delay(0.13), value: appear)
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "About")

            VStack(spacing: 0) {
                statRow(icon: "app.badge", iconColor: Color(hex: "5856D6"),
                        title: "Version", value: "1.0.0", valueColor: DS.Color.label2)
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
        .scaleEffect(appear ? 1 : 0.97)
        .opacity(appear ? 1 : 0)
        .animation(DS.Animation.spring.delay(0.17), value: appear)
    }

    // MARK: - Add QR sheet

    private var addQRSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    if pendingQRValue == nil {
                        // Label picker
                        Text("Name this location")
                            .font(DS.Font.sectionTitle)
                            .padding(.top, 8)

                        VStack(spacing: 10) {
                            ForEach(["Bathroom","Kitchen","Front Door","Desk"], id: \.self) { loc in
                                let sel = newQRLabel == loc
                                Button { newQRLabel = loc } label: {
                                    HStack {
                                        Text(loc).font(DS.Font.bodyBold)
                                            .foregroundStyle(sel ? .white : .primary)
                                        Spacer()
                                        if sel { Image(systemName: "checkmark").foregroundStyle(.white) }
                                    }
                                    .padding(DS.Layout.cardPadding)
                                    .background(sel ? DS.Color.accent : Color.appSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(PressEffectButtonStyle())
                            }

                            TextField("Custom label", text: $newQRLabel)
                                .textFieldStyle(.roundedBorder)
                                .font(DS.Font.body)
                        }
                        .padding(.horizontal, DS.Layout.screenPadding)

                        PrimaryButton("Scan QR Code", icon: "qrcode.viewfinder") {
                            showQRScanner = true
                        }
                        .padding(.horizontal, DS.Layout.screenPadding)
                    } else {
                        // Confirm
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DS.Color.success)
                            .shadow(color: DS.Color.success.opacity(0.4), radius: 16)
                        VStack(spacing: 6) {
                            Text("QR Scanned!").font(DS.Font.sectionTitle)
                            Text(newQRLabel).font(DS.Font.body).foregroundStyle(DS.Color.success)
                        }
                        Spacer()
                        PrimaryButton("Save QR Code", icon: "checkmark") {
                            if let v = pendingQRValue { QRManager.shared.add(label: newQRLabel, value: v) }
                            pendingQRValue = nil
                            showAddQR = false
                        }
                        .padding(.horizontal, DS.Layout.screenPadding)
                        Spacer().frame(height: 24)
                    }
                }
            }
            .navigationTitle("Add QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingQRValue = nil; showAddQR = false }
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .sheet(isPresented: $showQRScanner) {
                ZStack {
                    Color(hex: "0D0D0D").ignoresSafeArea()
                    VStack {
                        Text("Scan QR Code")
                            .font(DS.Font.sectionTitle)
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                        QRScannerView { value in
                            pendingQRValue = value
                            showQRScanner = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
