import Foundation

/// What one person shares with friends: their name, daily goal and the water
/// they drank on each of the last few weeks. Nothing else leaves the device.
nonisolated struct WaterSummary: Codable, Sendable, Hashable {
    /// How many days are shared. Four weeks covers this week and last week
    /// for any first weekday, with room to spare.
    static let sharedDays = 28

    var name: String
    var goalMilliliters: Double
    /// Milliliters per calendar day, keyed "yyyy-MM-dd" in the owner's
    /// calendar, so a friend in another time zone sees the owner's own days.
    var days: [String: Double]
    var updatedAt: Date

    init(name: String, goalMilliliters: Double, days: [String: Double], updatedAt: Date) {
        self.name = name
        self.goalMilliliters = goalMilliliters
        self.days = days
        self.updatedAt = updatedAt
    }

    /// Builds a summary from the app's own history (oldest first, ending today).
    init(name: String, goalMilliliters: Double, history: [DayTotal], updatedAt: Date = .now, calendar: Calendar = .current) {
        var days: [String: Double] = [:]
        for day in history.suffix(Self.sharedDays) {
            days[Self.key(for: day.date, calendar: calendar)] = (day.milliliters * 10).rounded() / 10
        }
        self.init(name: name, goalMilliliters: goalMilliliters, days: days, updatedAt: updatedAt)
    }

    func milliliters(on date: Date, calendar: Calendar = .current) -> Double {
        days[Self.key(for: date, calendar: calendar)] ?? 0
    }

    /// Same content, ignoring when it was made. Used to skip uploads that
    /// would change nothing.
    func hasSameContent(as other: WaterSummary) -> Bool {
        name == other.name && goalMilliliters == other.goalMilliliters && days == other.days
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Someone in the comparison: you, or a friend who shared with you.
nonisolated struct Participant: Identifiable, Sendable, Hashable {
    /// "me" for you; for a friend, their iCloud record owner id.
    let id: String
    let isMe: Bool
    let summary: WaterSummary

    static func me(_ summary: WaterSummary) -> Participant {
        Participant(id: "me", isMe: true, summary: summary)
    }
}

/// One person's numbers for one week.
nonisolated struct WeekStanding: Identifiable, Sendable, Hashable {
    let participant: Participant
    /// One entry per day of the week that has started, oldest first.
    let days: [DayTotal]
    let total: Double
    let dailyAverage: Double
    let daysGoalMet: Int
    /// Water drunk compared with what their own goal asked for over the same
    /// days (1 = exactly on goal). Ranking by this keeps it fair between
    /// people with different goals.
    let goalRatio: Double

    var id: String { participant.id }
}

/// Everyone's week side by side, best first.
nonisolated struct WeeklyComparison: Sendable {
    let weekStart: Date
    /// The days of the week that have started (all seven for a past week).
    let days: [Date]
    let standings: [WeekStanding]

    /// `weeksAgo` 0 is the current week, 1 the week before.
    init(participants: [Participant], weeksAgo: Int = 0, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let reference = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: today) ?? today
        let start = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        weekStart = start

        var days: [Date] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day <= today else { break }
            days.append(day)
        }
        self.days = days

        standings = participants.map { participant in
            let summary = participant.summary
            let totals = days.map { DayTotal(date: $0, milliliters: summary.milliliters(on: $0, calendar: calendar)) }
            let total = totals.reduce(0) { $0 + $1.milliliters }
            let goal = summary.goalMilliliters
            let expected = goal * Double(days.count)
            return WeekStanding(
                participant: participant,
                days: totals,
                total: total,
                dailyAverage: days.isEmpty ? 0 : total / Double(days.count),
                daysGoalMet: goal > 0 ? totals.count(where: { $0.milliliters >= goal }) : 0,
                goalRatio: expected > 0 ? total / expected : 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.goalRatio != rhs.goalRatio { return lhs.goalRatio > rhs.goalRatio }
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.participant.summary.name.localizedStandardCompare(rhs.participant.summary.name) == .orderedAscending
        }
    }
}
