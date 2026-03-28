import SwiftUI
import StoreKit

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var qrManager      = QRManager.shared
    @ObservedObject private var streakManager  = StreakManager.shared
    @ObservedObject private var premiumManager = PremiumManager.shared

    // QR management
    @State private var showAddQR          = false
    @State private var editingQREntry:  QRCodeEntry? = nil
    @State private var deletingQREntry: QRCodeEntry? = nil   // pending delete confirmation

    // Premium paywall
    @State private var showPaywall      = false

    // Privacy / FAQ
    @State private var showPrivacy      = false
    @State private var expandedFAQ: String? = nil

    @State private var appear           = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Layout.sectionSpacing) {
                        qrSection
                            .sectionAppear(appear, delay: 0.05)

                        streakSection
                            .sectionAppear(appear, delay: 0.09)

                        premiumSection
                            .sectionAppear(appear, delay: 0.13)

                        faqSection
                            .sectionAppear(appear, delay: 0.17)

                        legalSection
                            .sectionAppear(appear, delay: 0.21)

                        aboutSection
                            .sectionAppear(appear, delay: 0.25)

                        Spacer().frame(height: 48)
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
        // QR sheets
        .sheet(isPresented: $showAddQR)          { AddQRSheet() }
        .sheet(item: $editingQREntry)            { EditQRSheet(entry: $0) }
        // Premium paywall
        .sheet(isPresented: $showPaywall)        { PremiumPaywallView() }
        // Privacy
        .sheet(isPresented: $showPrivacy)        { PrivacyPolicyView() }
        // Delete confirmation
        .confirmationDialog(
            "Delete \"\(deletingQREntry?.label ?? "")\"?",
            isPresented: Binding(
                get:  { deletingQREntry != nil },
                set:  { if !$0 { deletingQREntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deletingQREntry {
                    withAnimation { qrManager.delete(entry) }
                }
                deletingQREntry = nil
            }
            Button("Cancel", role: .cancel) { deletingQREntry = nil }
        } message: {
            Text("This QR code will be removed and you will need to re-scan it to use it again.")
        }
        .onAppear {
            withAnimation(DS.Animation.spring.delay(0.05)) { appear = true }
        }
    }

    // =========================================================================
    // MARK: - QR Codes section
    // =========================================================================

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(
                title: "QR Codes",
                trailing: qrManager.canAddMore ? "+ Add" : nil,
                trailingAction: qrManager.canAddMore ? { showAddQR = true } : nil
            )

            VStack(spacing: 0) {
                if qrManager.entries.isEmpty {
                    emptyQRState
                } else {
                    ForEach(Array(qrManager.entries.enumerated()), id: \.element.id) { idx, entry in
                        VStack(spacing: 0) {
                            qrEntryRow(entry)
                            if idx < qrManager.entries.count - 1 {
                                Divider()
                                    .padding(.leading, DS.Layout.cardPadding)
                                    .opacity(0.35)
                            }
                        }
                    }
                }

                // Add button row or upgrade nudge at the bottom of the card
                if qrManager.canAddMore && !qrManager.entries.isEmpty {
                    Divider().padding(.leading, DS.Layout.cardPadding).opacity(0.35)
                    addQRRowButton
                } else if !qrManager.canAddMore && !premiumManager.isPremium {
                    Divider().padding(.leading, DS.Layout.cardPadding).opacity(0.35)
                    lockedQRRow
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
    }

    private func qrEntryRow(_ entry: QRCodeEntry) -> some View {
        HStack(spacing: 12) {

            // QR icon (changes based on code type)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.Color.success.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.typeIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Color.success)
            }

            // Label + primary badge + type badge + date + value preview
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(DS.Font.bodyBold)
                        .lineLimit(1)
                    if entry.isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(DS.Color.success)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DS.Color.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                // Type + date row
                HStack(spacing: 6) {
                    Text(entry.typeDisplayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DS.Color.accent.opacity(0.10))
                        .clipShape(Capsule())
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.label3)
                    Text("Added \(entry.createdAt, style: .date)")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.label3)
                }
                Text(String(entry.value.prefix(26)) + (entry.value.count > 26 ? "…" : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.label3)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // ── Always-visible action buttons ─────────────────────────────
            HStack(spacing: 6) {

                // Set as primary (only for non-primary entries)
                if !entry.isPrimary {
                    actionButton(
                        icon: "star.fill",
                        tint: Color(hex: "FFD700"),
                        help: "Set Primary"
                    ) {
                        withAnimation(DS.Animation.smooth) { qrManager.setPrimary(entry) }
                    }
                }

                // Edit label / re-scan
                actionButton(icon: "pencil", tint: DS.Color.accent, help: "Edit") {
                    editingQREntry = entry
                }

                // Delete (asks for confirmation)
                actionButton(icon: "trash", tint: DS.Color.danger, help: "Delete") {
                    deletingQREntry = entry
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, DS.Layout.cardPadding)
        .contentShape(Rectangle())
    }

    /// Small square icon button used in QR entry rows.
    private func actionButton(
        icon: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
    }

    private var emptyQRState: some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 28))
                .foregroundStyle(DS.Color.label3)
            Text("No QR codes yet")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.label3)
            Button("Set up QR Code") { showAddQR = true }
                .font(DS.Font.captionBold)
                .foregroundStyle(DS.Color.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var addQRRowButton: some View {
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
    }

    private var lockedQRRow: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.streak)
                Text("Upgrade for multiple QR codes")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.label2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.label3)
            }
            .padding(DS.Layout.cardPadding)
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    // =========================================================================
    // MARK: - Streak section
    // =========================================================================

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Wake-up Streak")
            VStack(spacing: 0) {
                statRow(icon: "flame.fill",        iconColor: DS.Color.streak,
                        title: "Current streak",   value: "\(streakManager.data.currentStreak) days",
                        valueColor: DS.Color.streak)
                Divider().padding(.leading, 60).opacity(0.4)
                statRow(icon: "trophy.fill",       iconColor: Color(hex: "FFD700"),
                        title: "Longest streak",   value: "\(streakManager.data.longestStreak) days",
                        valueColor: Color(hex: "FFD700"))
                Divider().padding(.leading, 60).opacity(0.4)
                statRow(icon: "checkmark.circle.fill", iconColor: DS.Color.success,
                        title: "Total successes",  value: "\(streakManager.data.totalSuccesses)",
                        valueColor: DS.Color.success)
                if premiumManager.isPremium {
                    Divider().padding(.leading, 60).opacity(0.4)
                    statRow(icon: "snowflake",     iconColor: DS.Color.accent,
                            title: "Streak freezes", value: "\(streakManager.data.freezesRemaining) left",
                            valueColor: DS.Color.accent)
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
    }

    private func statRow(icon: String, iconColor: Color,
                         title: String, value: String, valueColor: Color) -> some View {
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
            Text(value).font(DS.Font.bodyBold).foregroundStyle(valueColor)
        }
        .padding(DS.Layout.cardPadding)
    }

    // =========================================================================
    // MARK: - Premium section
    // =========================================================================

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Premium")

            if premiumManager.isPremium {
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
                        Text("All features unlocked").font(DS.Font.caption)
                            .foregroundStyle(DS.Color.label2)
                    }
                    Spacer()
                }
                .padding(DS.Layout.cardPadding)
                .cardStyle()
                .padding(.horizontal, DS.Layout.screenPadding)
            } else {
                Button { showPaywall = true } label: {
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
                            if let p = premiumManager.product {
                                Text("Unlimited alarms · Multiple QR · \(p.displayPrice) lifetime")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.label2)
                            } else {
                                Text("Unlimited alarms · Multiple QR · $4.99 lifetime")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.label2)
                            }
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
                    .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius,
                            y: DS.Shadow.card.y)
                }
                .buttonStyle(PressEffectButtonStyle())
                .padding(.horizontal, DS.Layout.screenPadding)
            }
        }
    }

    // =========================================================================
    // MARK: - FAQ section
    // =========================================================================

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "FAQ")
            VStack(spacing: 0) {
                ForEach(Array(FAQItem.all.enumerated()), id: \.element.question) { idx, item in
                    VStack(spacing: 0) {
                        FAQRow(item: item, expanded: expandedFAQ == item.question) {
                            withAnimation(DS.Animation.smooth) {
                                expandedFAQ = expandedFAQ == item.question ? nil : item.question
                            }
                        }
                        if idx < FAQItem.all.count - 1 {
                            Divider().padding(.leading, 16).opacity(0.4)
                        }
                    }
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
    }

    // =========================================================================
    // MARK: - Legal section
    // =========================================================================

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Privacy & Legal")
            VStack(spacing: 0) {
                linkRow(icon: "hand.raised.fill", iconColor: DS.Color.accent,
                        title: "Privacy Policy") {
                    if let url = URL(string: "https://manhcuong5311-hue.github.io/WakeAlarm/") {
                        UIApplication.shared.open(url)
                    }
                }
                Divider().padding(.leading, 60).opacity(0.4)
                linkRow(icon: "doc.text.fill", iconColor: Color(hex: "5856D6"),
                        title: "Terms of Use (EULA)") {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        UIApplication.shared.open(url)
                    }
                }
                Divider().padding(.leading, 60).opacity(0.4)
                // Restore purchases row with loading indicator
                Button {
                    Task { await premiumManager.restorePurchases() }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DS.Color.success.opacity(0.15))
                                .frame(width: 32, height: 32)
                            if premiumManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DS.Color.success)
                            }
                        }
                        Text("Restore Purchases")
                            .font(DS.Font.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Color.label3)
                    }
                    .padding(DS.Layout.cardPadding)
                }
                .buttonStyle(PressEffectButtonStyle())
                .disabled(premiumManager.isLoading)
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)

            if let error = premiumManager.purchaseError {
                Text(error)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.danger)
                    .padding(.horizontal, DS.Layout.screenPadding + DS.Layout.cardPadding)
            }
        }
    }

    private func linkRow(icon: String, iconColor: Color,
                         title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                Text(title).font(DS.Font.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.label3)
            }
            .padding(DS.Layout.cardPadding)
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    // =========================================================================
    // MARK: - About section
    // =========================================================================

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "About")
            VStack(spacing: 0) {
                statRow(icon: "app.badge",         iconColor: Color(hex: "5856D6"),
                        title: "Version",           value: appVersion,
                        valueColor: DS.Color.label2)
                Divider().padding(.leading, 60).opacity(0.4)
                linkRow(icon: "star.fill",          iconColor: Color(hex: "FFD700"),
                        title: "Rate WakeLock") {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
                Divider().padding(.leading, 60).opacity(0.4)
                linkRow(icon: "envelope.fill",      iconColor: DS.Color.accent,
                        title: "Contact Support") {
                    if let url = URL(string: "mailto:Manhcuong531@gmail.com") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .cardStyle()
            .padding(.horizontal, DS.Layout.screenPadding)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - FAQ data

struct FAQItem {
    let question: String
    let answer: String

    static let all: [FAQItem] = [
        .init(
            question: "How does WakeLock work?",
            answer: "WakeLock forces you to physically get out of bed to scan a QR code placed in another room. The alarm keeps ringing and escalating until you walk to that location and scan it."
        ),
        .init(
            question: "What if my phone is on silent?",
            answer: "WakeLock uses a special audio session (AVAudioSession .playback category) that bypasses the silent/ring switch. Your alarm will ring at full volume even when your phone is muted."
        ),
        .init(
            question: "What happens if I force-quit the app?",
            answer: "WakeLock detects force-quit on the next launch and counts it as a failed wake-up, breaking your streak. Burst notifications continue ringing every 15 seconds for up to 7.5 minutes after the alarm fires."
        ),
        .init(
            question: "Why do I need a QR code?",
            answer: "A QR code in another room ensures you physically get up and move to dismiss the alarm — not just tap your phone from bed. No QR scan = no dismissal."
        ),
        .init(
            question: "Can I use Face ID instead of QR?",
            answer: "Face ID / Touch ID can be enabled as an alternative dismiss method when creating an alarm. However, for maximum accountability, QR-only mode is recommended."
        ),
        .init(
            question: "What's included in Premium?",
            answer: "Premium unlocks: multiple QR codes (different rooms can each dismiss your alarm), streak freezes (miss one day without breaking your streak), and priority support."
        ),
        .init(
            question: "How do streak freezes work?",
            answer: "A streak freeze protects your streak for one missed morning. Premium users start with 3 freezes. Freezes are automatically applied when you miss a morning — you don't need to do anything."
        ),
        .init(
            question: "Can I change or delete a QR code?",
            answer: "Yes. Go to Settings → QR Codes and tap any entry to edit its label or re-scan a new QR code. Swipe left to delete or right to set as primary."
        ),
    ]
}

// MARK: - FAQ Row

struct FAQRow: View {
    let item: FAQItem
    let expanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(item.question)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.label3)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(DS.Animation.smooth, value: expanded)
                }
                .padding(DS.Layout.cardPadding)
            }
            .buttonStyle(PressEffectButtonStyle())

            if expanded {
                Text(item.answer)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.label2)
                    .padding(.horizontal, DS.Layout.cardPadding)
                    .padding(.bottom, DS.Layout.cardPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Premium Paywall View

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pm = PremiumManager.shared

    private struct Feature {
        let icon: String; let color: Color
        let title: String; let subtitle: String
    }
    private let features: [Feature] = [
        Feature(icon: "alarm.fill",            color: DS.Color.accent,
                title: "Unlimited Alarms",      subtitle: "Free tier is limited to 2 alarms"),
        Feature(icon: "qrcode.viewfinder",     color: DS.Color.success,
                title: "Multiple QR Codes",     subtitle: "Place codes in different rooms"),
        Feature(icon: "snowflake",             color: Color(hex: "5AC8FA"),
                title: "Streak Freeze",         subtitle: "Miss one day without breaking your streak"),
        Feature(icon: "person.fill.checkmark", color: Color(hex: "5856D6"),
                title: "Priority Support",      subtitle: "Direct email support"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // ── Hero ──────────────────────────────────────────────
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(DS.Gradient.accent)
                                    .frame(width: 90, height: 90)
                                    .shadow(color: DS.Color.accent.opacity(0.45), radius: 24, y: 10)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("LIFETIME ACCESS")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.5)
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(DS.Color.accent.opacity(0.12))
                                .clipShape(Capsule())
                            Text("WakeLock Premium")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            // Big price
                            (Text(pm.product?.displayPrice ?? "$4.99")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                             + Text(" one-time")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(DS.Color.label2))
                            .foregroundStyle(.primary)

                            Text("Pay once. Yours forever. No subscription.")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.label2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 28)
                        .padding(.horizontal, DS.Layout.screenPadding)

                        // ── Feature list ──────────────────────────────────────
                        VStack(spacing: 0) {
                            ForEach(Array(features.enumerated()), id: \.offset) { idx, f in
                                featureRow(f)
                                if idx < features.count - 1 {
                                    Divider().padding(.leading, 60).opacity(0.4)
                                }
                            }
                        }
                        .cardStyle()
                        .padding(.horizontal, DS.Layout.screenPadding)

                        // ── Purchase CTA ──────────────────────────────────────
                        VStack(spacing: 14) {
                            if pm.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: DS.Layout.buttonHeight)
                            } else {
                                PrimaryButton(
                                    pm.product != nil
                                        ? "Get Lifetime Access · \(pm.product!.displayPrice)"
                                        : "Get Lifetime Access",
                                    icon: "star.fill"
                                ) { Task { await pm.purchase() } }
                                .padding(.horizontal, DS.Layout.screenPadding)
                            }

                            if let error = pm.purchaseError {
                                Text(error)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.danger)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, DS.Layout.screenPadding)
                            }

                            Button {
                                Task { await pm.restorePurchases() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Restore Purchases")
                                        .font(DS.Font.caption)
                                }
                                .foregroundStyle(DS.Color.label2)
                            }
                            .disabled(pm.isLoading)
                        }

                        // ── How this purchase works ────────────────────────────
                        VStack(alignment: .leading, spacing: 0) {
                            Text("How this purchase works")
                                .font(DS.Font.captionBold)
                                .foregroundStyle(DS.Color.label2)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .padding(.horizontal, DS.Layout.cardPadding)
                                .padding(.top, DS.Layout.cardPadding)
                                .padding(.bottom, 10)
                            Divider().opacity(0.4)
                            howItWorksRow(num: "1", text: "Tap the button above to start a secure payment via Apple.")
                            Divider().padding(.leading, 52).opacity(0.4)
                            howItWorksRow(num: "2", text: "Apple processes your payment — we never see your card details.")
                            Divider().padding(.leading, 52).opacity(0.4)
                            howItWorksRow(num: "3", text: "Premium is tied to your Apple ID and automatically restores on all your devices.")
                            Divider().padding(.leading, 52).opacity(0.4)
                            howItWorksRow(num: "4", text: "One-time payment only — no subscription, no recurring charges.")
                        }
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous))
                        .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)
                        .padding(.horizontal, DS.Layout.screenPadding)

                        // ── Legal links ────────────────────────────────────────
                        HStack(spacing: 6) {
                            Button("Privacy Policy") {
                                if let url = URL(string: "https://manhcuong5311-hue.github.io/WakeAlarm/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Text("·").foregroundStyle(DS.Color.label3)
                            Button("Terms of Use (EULA)") {
                                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.label3)

                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(DS.Color.accent)
                }
            }
        }
        .onChange(of: pm.isPremium) { _, v in if v { dismiss() } }
    }

    private func featureRow(_ f: Feature) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(f.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: f.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(f.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(DS.Font.bodyBold)
                Text(f.subtitle).font(DS.Font.caption).foregroundStyle(DS.Color.label2)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.Color.success)
        }
        .padding(DS.Layout.cardPadding)
    }

    private func howItWorksRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(DS.Color.accent.opacity(0.15)).frame(width: 28, height: 28)
                Text(num)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(DS.Color.accent)
            }
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Layout.cardPadding)
    }
}

// MARK: - Add QR Sheet

struct AddQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label         = "Bathroom"
    @State private var pendingValue: String? = nil
    @State private var pendingType: String   = "org.iso.QRCode"
    @State private var showScanner   = false

    private let presets = ["Bathroom", "Kitchen", "Front Door", "Desk", "Bedroom"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    if pendingValue == nil {
                        // Step 1: choose label
                        Text("Where is your QR code?")
                            .font(DS.Font.sectionTitle)
                            .padding(.top, 8)

                        VStack(spacing: 8) {
                            ForEach(presets, id: \.self) { loc in
                                let selected = label == loc
                                Button { label = loc } label: {
                                    HStack {
                                        Text(loc).font(DS.Font.bodyBold)
                                            .foregroundStyle(selected ? .white : .primary)
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(DS.Layout.cardPadding)
                                    .background(selected ? DS.Color.accent : Color.appSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(PressEffectButtonStyle())
                            }

                            TextField("Custom label…", text: $label)
                                .padding(DS.Layout.cardPadding)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, DS.Layout.screenPadding)

                        PrimaryButton("Scan QR Code", icon: "qrcode.viewfinder") {
                            showScanner = true
                        }
                        .padding(.horizontal, DS.Layout.screenPadding)

                    } else {
                        // Step 2: confirm
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(DS.Color.success)
                            .shadow(color: DS.Color.success.opacity(0.4), radius: 20)
                        VStack(spacing: 6) {
                            Text("QR Code Scanned!").font(DS.Font.sectionTitle)
                            Text(label).font(DS.Font.body).foregroundStyle(DS.Color.success)
                        }
                        Spacer()
                        PrimaryButton("Save QR Code", icon: "checkmark") {
                            if let v = pendingValue {
                                QRManager.shared.add(label: label, value: v, codeType: pendingType)
                            }
                            dismiss()
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
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { value, type in
                    pendingValue = value
                    pendingType  = type
                    showScanner  = false
                }
            }
        }
    }
}

// MARK: - Edit QR Sheet

struct EditQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: QRCodeEntry

    @State private var label         = ""
    @State private var showRescan    = false
    @State private var rescanned     = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 24) {
                    // QR icon
                    ZStack {
                        Circle()
                            .fill(DS.Color.success.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: rescanned ? "checkmark.circle.fill" : "qrcode")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(rescanned ? DS.Color.success : DS.Color.success)
                    }
                    .padding(.top, 16)

                    // Label field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location Label")
                            .font(DS.Font.captionBold)
                            .foregroundStyle(DS.Color.label2)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        TextField("e.g. Bathroom", text: $label)
                            .font(DS.Font.bodyBold)
                            .padding(DS.Layout.cardPadding)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, DS.Layout.screenPadding)

                    // Re-scan button
                    Button {
                        showRescan = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 16, weight: .medium))
                            Text(rescanned ? "Re-scan Again" : "Scan New QR Code")
                                .font(DS.Font.bodyBold)
                        }
                        .foregroundStyle(DS.Color.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.Layout.buttonHeight)
                        .background(DS.Color.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressEffectButtonStyle())
                    .padding(.horizontal, DS.Layout.screenPadding)

                    Spacer()

                    // Save
                    PrimaryButton("Save Changes", icon: "checkmark") {
                        QRManager.shared.updateLabel(entry, label: label)
                        dismiss()
                    }
                    .padding(.horizontal, DS.Layout.screenPadding)
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer().frame(height: 24)
                }
            }
            .navigationTitle("Edit QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .sheet(isPresented: $showRescan) {
                QRScannerSheet { value, type in
                    QRManager.shared.rescan(entry, newValue: value, newType: type)
                    rescanned   = true
                    showRescan  = false
                }
            }
        }
        .onAppear { label = entry.label }
    }
}

// MARK: - QR Scanner Sheet (shared helper)

struct QRScannerSheet: View {
    /// Called with (rawValue, codeTypeRawValue)
    let onScan: (String, String) -> Void

    var body: some View {
        ZStack {
            Color(hex: "0D0D0D").ignoresSafeArea()
            VStack {
                Text("Scan QR Code")
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                QRScannerView(onDetected: onScan)
            }
        }
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── View online banner ────────────────────────────────
                        Button {
                            if let url = URL(string: "https://manhcuong5311-hue.github.io/WakeAlarm/") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DS.Color.accent)
                                Text("View Full Policy Online")
                                    .font(DS.Font.bodyBold)
                                    .foregroundStyle(DS.Color.accent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Color.accent)
                            }
                            .padding(DS.Layout.cardPadding)
                            .background(DS.Color.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Color.accent.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PressEffectButtonStyle())

                        policySection(
                            title: "Overview",
                            body: "WakeLock does not collect, transmit, or share any personal data. Everything stays on your device — no servers, no cloud sync, no tracking."
                        )
                        policySection(
                            title: "Data Storage (Local Only)",
                            body: "• Alarm settings (time, label, repeat days)\n• QR code values — stored securely in iOS Keychain\n• Wake-up streak data\n• Premium purchase status — verified via StoreKit 2"
                        )
                        policySection(
                            title: "Data NOT Collected",
                            body: "• No analytics or usage tracking\n• No crash reporting\n• No advertising identifiers\n• No location data\n• No microphone or camera storage/transmission\n• No account creation or user profiles"
                        )
                        policySection(
                            title: "Permissions",
                            body: "• Camera — QR code scanning only, no storage\n• Notifications — local and on-device only\n• Face ID / Touch ID — optional, for alarm dismissal only. Biometric data never leaves your device."
                        )
                        policySection(
                            title: "Third-Party Services",
                            body: "Apple's StoreKit 2 handles all payments. We receive no payment details. Users are directed to Apple's Privacy Policy for additional information."
                        )
                        policySection(
                            title: "Data Deletion",
                            body: "Uninstalling WakeLock removes all app data and Keychain entries per iOS default behaviour."
                        )
                        policySection(
                            title: "Contact",
                            body: "Questions about privacy? Email manhcuong531@gmail.com"
                        )

                        Text("Last updated: March 2025")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.label3)
                            .padding(.top, 8)

                        Spacer().frame(height: 40)
                    }
                    .padding(DS.Layout.screenPadding)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Font.bodyBold)
            Text(body)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - View modifier helper

private extension View {
    func sectionAppear(_ appear: Bool, delay: Double) -> some View {
        self
            .scaleEffect(appear ? 1 : 0.97)
            .opacity(appear ? 1 : 0)
            .animation(DS.Animation.spring.delay(delay), value: appear)
    }
}

#Preview {
    SettingsView()
}
