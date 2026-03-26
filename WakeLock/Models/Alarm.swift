import Foundation

/// Repeat pattern for alarms
enum AlarmRepeat: String, Codable, CaseIterable {
    case once = "Once"
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case custom = "Custom"
}

/// Core alarm model
struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var time: Date
    var repeatPattern: AlarmRepeat
    var customDays: Set<Int>   // 1=Sunday ... 7=Saturday (Calendar weekday)
    var isEnabled: Bool
    var requiresQR: Bool       // must scan QR to dismiss
    var allowsBiometrics: Bool // allow Face ID / Touch ID as fallback
    var createdAt: Date = Date()

    /// Human-readable time string
    var timeString: String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: time)
    }

    /// Subtitle showing repeat info
    var repeatDescription: String {
        switch repeatPattern {
        case .once:     return "One time"
        case .daily:    return "Every day"
        case .weekdays: return "Mon – Fri"
        case .weekends: return "Sat – Sun"
        case .custom:
            let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            let sorted = customDays.sorted()
            return sorted.map { names[($0 - 1) % 7] }.joined(separator: ", ")
        }
    }

    /// Returns the weekday integers this alarm fires on (1=Sun)
    var activeDays: Set<Int> {
        switch repeatPattern {
        case .once:     return []
        case .daily:    return Set(1...7)
        case .weekdays: return Set([2,3,4,5,6])
        case .weekends: return Set([1,7])
        case .custom:   return customDays
        }
    }
}
