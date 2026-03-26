import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget entry point

struct AlarmLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            // Lock screen / notification-centre banner
            AlarmLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded view (long-press or always-on display) ───────────
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(escalationColor(context.state.escalationLevel))
                        Text("ALARM")
                            .font(.caption.bold())
                            .tracking(1)
                            .foregroundStyle(escalationColor(context.state.escalationLevel))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.alarmTime, style: .time)
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            if !context.attributes.label.isEmpty {
                                Text(context.attributes.label)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            Text(elapsedText(context.state.elapsedSeconds))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Spacer()

                        Link(destination: deepLinkURL(context.attributes.alarmId)) {
                            Text("Open to Stop")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(escalationColor(context.state.escalationLevel))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                }

            } compactLeading: {
                // ── Compact leading (pill left side) ─────────────────────────
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(escalationColor(context.state.escalationLevel))

            } compactTrailing: {
                // ── Compact trailing (pill right side) ───────────────────────
                Text(context.attributes.alarmTime, style: .time)
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)

            } minimal: {
                // ── Minimal (small circular indicator) ───────────────────────
                Image(systemName: "alarm.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(escalationColor(context.state.escalationLevel))
            }
            .widgetURL(deepLinkURL(context.attributes.alarmId))
            .keylineTint(escalationColor(context.state.escalationLevel))
        }
    }

    // MARK: - Helpers

    private func escalationColor(_ level: Int) -> Color {
        switch level {
        case 1:  return Color(red: 1.0, green: 0.60, blue: 0.0)  // orange
        case 2:  return Color(red: 1.0, green: 0.23, blue: 0.19) // iOS red
        default: return Color(red: 0.9, green: 0.0,  blue: 0.0)  // deep red
        }
    }

    private func elapsedText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s ringing" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m ringing" : "\(m)m \(s)s ringing"
    }

    private func deepLinkURL(_ alarmId: String) -> URL {
        URL(string: "wakelock://ring/\(alarmId)")!
    }
}

// MARK: - Lock screen / banner view

struct AlarmLockScreenView: View {

    let context: ActivityViewContext<AlarmActivityAttributes>

    private var level: Int { context.state.escalationLevel }

    private var accentColor: Color {
        switch level {
        case 1:  return Color(red: 1.0, green: 0.60, blue: 0.0)
        case 2:  return Color(red: 1.0, green: 0.23, blue: 0.19)
        default: return Color(red: 0.9, green: 0.0,  blue: 0.0)
        }
    }

    private var bgGradient: LinearGradient {
        switch level {
        case 1:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.07, blue: 0.0),
                         Color(red: 0.07, green: 0.04, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2:
            return LinearGradient(
                colors: [Color(red: 0.18, green: 0.02, blue: 0.0),
                         Color(red: 0.10, green: 0.01, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(
                colors: [Color(red: 0.22, green: 0.0, blue: 0.0),
                         Color(red: 0.12, green: 0.0, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        HStack(spacing: 14) {

            // Alarm icon badge
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "alarm.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            // Centre: label + time + elapsed
            VStack(alignment: .leading, spacing: 4) {
                Text(level >= 3 ? "GET UP NOW" : "ALARM RINGING")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(accentColor)

                Text(context.attributes.alarmTime, style: .time)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                if !context.attributes.label.isEmpty {
                    Text(context.attributes.label)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            // CTA button
            Link(destination: URL(string: "wakelock://ring/\(context.attributes.alarmId)")!) {
                VStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Text("to dismiss")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(bgGradient)
    }
}
