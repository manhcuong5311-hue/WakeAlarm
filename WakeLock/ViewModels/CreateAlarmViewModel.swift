import Foundation
import Combine

final class CreateAlarmViewModel: ObservableObject {

    // Form fields
    @Published var selectedTime: Date = {
        // Default: next round hour
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }()

    @Published var label: String = ""
    @Published var repeatPattern: AlarmRepeat = .daily
    @Published var customDays: Set<Int> = []
    @Published var requiresQR: Bool = true
    @Published var allowsBiometrics: Bool = true

    // Editing an existing alarm
    var editingAlarm: Alarm?

    init(editing alarm: Alarm? = nil) {
        if let alarm {
            editingAlarm = alarm
            selectedTime   = alarm.time
            label          = alarm.label
            repeatPattern  = alarm.repeatPattern
            customDays     = alarm.customDays
            requiresQR     = alarm.requiresQR
            allowsBiometrics = alarm.allowsBiometrics
        }
    }

    var isValid: Bool {
        repeatPattern != .custom || !customDays.isEmpty
    }

    func save() {
        guard isValid else { return }

        if var existing = editingAlarm {
            existing.time          = selectedTime
            existing.label         = label
            existing.repeatPattern = repeatPattern
            existing.customDays    = customDays
            existing.requiresQR    = requiresQR
            existing.allowsBiometrics = allowsBiometrics
            AlarmManager.shared.update(existing)
        } else {
            let alarm = Alarm(
                label:          label,
                time:           selectedTime,
                repeatPattern:  repeatPattern,
                customDays:     customDays,
                isEnabled:      true,
                requiresQR:     requiresQR,
                allowsBiometrics: allowsBiometrics
            )
            AlarmManager.shared.add(alarm)
        }
    }
}
