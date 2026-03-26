import Foundation
import Combine

private let kStreakKey = "wakelock.streak"

/// Tracks wake-up streaks and milestones.
final class StreakManager: ObservableObject {

    static let shared = StreakManager()
    private init() { load() }

    @Published private(set) var data: StreakData = StreakData()

    // MARK: - Record outcomes

    /// Call when user successfully dismissed alarm within allowed window
    func recordSuccess() {
        let today = Calendar.current.startOfDay(for: Date())

        // Avoid double-counting same day
        if let last = data.lastSuccessDate,
           Calendar.current.isDate(last, inSameDayAs: today) { return }

        // Check if streak is still active (dismissed alarm yesterday or today)
        let isConsecutive: Bool
        if let last = data.lastSuccessDate {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            isConsecutive = Calendar.current.isDate(last, inSameDayAs: yesterday) ||
                            Calendar.current.isDate(last, inSameDayAs: today)
        } else {
            isConsecutive = false
        }

        data.currentStreak = isConsecutive ? data.currentStreak + 1 : 1
        data.longestStreak = max(data.longestStreak, data.currentStreak)
        data.lastSuccessDate = today
        data.totalSuccesses += 1
        data.weeklyHistory.append(today)
        // Keep last 30 entries
        if data.weeklyHistory.count > 30 { data.weeklyHistory.removeFirst() }

        save()
    }

    /// Call when alarm was missed / app killed during alarm / user timed out
    func recordFailure(useFreeze: Bool = false) {
        if useFreeze && data.freezesRemaining > 0 {
            data.freezesRemaining -= 1
            save()
            return
        }
        data.currentStreak = 0
        save()
    }

    // MARK: - Queries

    var streakEmoji: String {
        guard data.currentStreak > 0 else { return "😴" }
        return data.latestMilestone?.emoji ?? "🔥"
    }

    var milestoneJustReached: Milestone? {
        kMilestones.first { $0.days == data.currentStreak }
    }

    // MARK: - Persistence

    private func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: kStreakKey)
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: kStreakKey),
              let decoded = try? JSONDecoder().decode(StreakData.self, from: d) else { return }
        data = decoded
    }
}
