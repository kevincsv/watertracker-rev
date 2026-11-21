import Foundation

/// Remembers what the daily goal was on each day, so History judges a past
/// day by the goal it had then and not by today's. Kept in this device's own
/// defaults; days from before this existed fall back to the current goal.
nonisolated enum GoalHistory {
    private static let key = "goalByDay"
    static let keptDays = 400

    /// Goals in milliliters keyed "yyyy-MM-dd".
    static func load(defaults: UserDefaults = .standard) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func record(_ goal: Double, on date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        guard goal > 0 else { return }
        var goals = load(defaults: defaults)
        let today = WaterSummary.key(for: date, calendar: calendar)
        guard goals[today] != goal else { return }
        goals[today] = goal
        if goals.count > keptDays, let oldest = calendar.date(byAdding: .day, value: -keptDays, to: date) {
            let cutoff = WaterSummary.key(for: oldest, calendar: calendar)
            goals = goals.filter { $0.key >= cutoff }
        }
        defaults.set(goals, forKey: key)
    }

    static func goal(on date: Date, in goals: [String: Double], fallback: Double, calendar: Calendar = .current) -> Double {
        goals[WaterSummary.key(for: date, calendar: calendar)] ?? fallback
    }
}
