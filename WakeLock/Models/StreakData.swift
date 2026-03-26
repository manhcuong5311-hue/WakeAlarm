import Foundation

/// Milestone definitions
struct Milestone: Identifiable {
    let id = UUID()
    let days: Int
    let title: String
    let emoji: String
}

let kMilestones: [Milestone] = [
    Milestone(days: 3,  title: "Getting Started",  emoji: "🌱"),
    Milestone(days: 7,  title: "Disciplined",       emoji: "💪"),
    Milestone(days: 14, title: "Committed",         emoji: "🎯"),
    Milestone(days: 30, title: "Unstoppable",       emoji: "🔥"),
    Milestone(days: 60, title: "Legendary",         emoji: "⚡️"),
]

/// Persisted streak state
struct StreakData: Codable {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastSuccessDate: Date? = nil
    var totalSuccesses: Int = 0
    var freezesRemaining: Int = 1   // premium feature – one skip per week
    var weeklyHistory: [Date] = []  // dates of successful wake-ups

    /// Next milestone the user is working toward
    var nextMilestone: Milestone? {
        kMilestones.first { $0.days > currentStreak }
    }

    /// Most recently achieved milestone
    var latestMilestone: Milestone? {
        kMilestones.filter { $0.days <= currentStreak }.last
    }
}
