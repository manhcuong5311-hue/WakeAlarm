import SwiftUI

// MARK: - Primary Button

struct PrimaryButton: View {
    let title: String
    let icon: String?
    var style: Style = .accent
    let action: () -> Void

    enum Style { case accent, danger, ghost }

    init(_ title: String, icon: String? = nil, style: Style = .accent, action: @escaping () -> Void) {
        self.title  = title
        self.icon   = icon
        self.style  = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(DS.Font.bodyBold)
                    .tracking(0.2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.buttonHeight)
            .foregroundStyle(.white)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: shadowColor,
                radius: DS.Shadow.button.radius,
                y: DS.Shadow.button.y
            )
        }
        .buttonStyle(PressEffectButtonStyle())
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .accent:  DS.Gradient.accent
        case .danger:  LinearGradient(colors: [DS.Color.danger, Color(hex: "C0392B")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ghost:   Color.primary.opacity(0.08)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .accent: return Color(hex: "4A90E2").opacity(0.4)
        case .danger: return DS.Color.danger.opacity(0.4)
        case .ghost:  return .clear
        }
    }
}

// MARK: - Ghost Button

struct GhostButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title  = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.label2)
        }
        .buttonStyle(PressEffectButtonStyle())
    }
}

// MARK: - WLButton (legacy alias for existing call sites)

struct WLButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title  = title
        self.icon   = icon
        self.action = action
    }

    var body: some View {
        PrimaryButton(title, icon: icon, action: action)
    }
}

// MARK: - WLCard (legacy alias)

struct WLCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DS.Layout.cardPadding)
            .cardStyle()
    }
}

// MARK: - Streak Banner

struct StreakBannerView: View {
    @ObservedObject private var sm = StreakManager.shared
    @State private var appear = false

    var body: some View {
        HStack(spacing: 16) {
            // Flame + number
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 28))
                        .shadow(color: DS.Color.streak.opacity(0.6), radius: 8, y: 0)
                    Text("\(sm.data.currentStreak)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [DS.Color.streak, Color(hex: "FF6B00")],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .contentTransition(.numericText())
                        .animation(DS.Animation.spring, value: sm.data.currentStreak)
                }
                Text(sm.data.currentStreak == 0 ? "Start your streak" : "Day streak · Don't break it")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.label2)
            }

            Spacer()

            // Badge / next milestone
            VStack(alignment: .trailing, spacing: 4) {
                if let m = sm.data.latestMilestone {
                    Text(m.emoji)
                        .font(.title2)
                    Text(m.title)
                        .font(DS.Font.captionBold)
                        .foregroundStyle(DS.Color.streak)
                } else if let next = sm.data.nextMilestone {
                    Text("\(next.days - sm.data.currentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Color.label2)
                    Text("days to \(next.title)")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.label3)
                }
            }
        }
        .padding(DS.Layout.cardPadding)
        .background(
            ZStack {
                DS.Gradient.streakCard
                // Subtle warm glow when streak > 0
                if sm.data.currentStreak > 0 {
                    RadialGradient(
                        colors: [DS.Color.streak.opacity(0.12), .clear],
                        center: .topLeading, startRadius: 0, endRadius: 160
                    )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .continuous)
                .stroke(DS.Color.streak.opacity(sm.data.currentStreak > 0 ? 0.2 : 0.05), lineWidth: 1)
        )
        .shadow(color: sm.data.currentStreak > 0 ? DS.Shadow.streak.color : .clear,
                radius: DS.Shadow.streak.radius, y: DS.Shadow.streak.y)
        .scaleEffect(appear ? 1 : 0.95)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(DS.Animation.spring.delay(0.1)) { appear = true }
        }
    }
}

// MARK: - Alarm Card

struct AlarmCardView: View {
    let alarm: Alarm
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onEdit: () -> Void

    @State private var appear = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: time + meta — tap to edit
            VStack(alignment: .leading, spacing: 6) {
                Text(alarm.timeString)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(alarm.isEnabled ? .primary : DS.Color.label3)
                    .animation(DS.Animation.snappy, value: alarm.isEnabled)

                HStack(spacing: 8) {
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.label2)
                    }
                    Text(alarm.repeatDescription)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.label3)
                }

                // Dismiss badges
                HStack(spacing: 6) {
                    if alarm.requiresQR {
                        dismissBadge("qrcode", color: DS.Color.success)
                    }
                    if alarm.allowsBiometrics {
                        dismissBadge("faceid", color: DS.Color.accent)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Spacer()

            // Right: toggle
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(DS.Color.accent)
        }
        .padding(DS.Layout.cardPadding)
        .cardStyle()
        // Disabled state: subtle desaturation overlay
        .opacity(alarm.isEnabled ? 1.0 : 0.55)
        .animation(DS.Animation.snappy, value: alarm.isEnabled)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(DS.Color.accent)
        }
        .scaleEffect(appear ? 1 : 0.96)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(DS.Animation.spring) { appear = true }
        }
    }

    private func dismissBadge(_ icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - Empty State

struct EmptyAlarmsView: View {
    var onAdd: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DS.Color.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "alarm")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(spacing: 8) {
                Text("No Alarms")
                    .font(DS.Font.sectionTitle)
                Text("Create your first alarm and start\nbuilding the discipline to wake up.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.label2)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton("Create First Alarm", icon: "plus") { onAdd() }
                .padding(.horizontal, 32)
        }
        .padding(DS.Layout.screenPadding)
        .scaleEffect(appear ? 1 : 0.94)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(DS.Animation.spring.delay(0.15)) { appear = true }
        }
    }
}

// MARK: - Section Header

struct SectionHeaderView: View {
    let title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Font.captionBold)
                .foregroundStyle(DS.Color.label2)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            if let t = trailing {
                if let action = trailingAction {
                    Button(t, action: action)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.accent)
                } else {
                    Text(t)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.label3)
                }
            }
        }
        .padding(.horizontal, DS.Layout.screenPadding)
    }
}

// MARK: - Setting Row

struct SettingRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(DS.Font.body)
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }
}
