import Foundation

/// What the app knows about one past day.
nonisolated struct DayEnergy: Hashable, Sendable {
    let date: Date
    /// Calories eaten, from every app that writes to Health. Zero means the
    /// day was not logged.
    let intake: Double
    /// Workout calories that day, without duplicates.
    let exercise: Double
}

/// Daily burn learned from real intake and the weight trend.
nonisolated struct AdaptiveEstimate: Sendable, Equatable {
    /// Total daily energy expenditure, workouts included.
    let tdee: Double
    /// Expenditure without workouts.
    let baseline: Double
    /// 0...1, how much to trust it.
    let confidence: Double
    let loggedDays: Int
}

/// Energy balance: if you ate X a day on average and the trend moved by Y kg,
/// you burned X − Y × 7700 / days. This is the approach adaptive apps such as
/// MacroFactor use, here in its simplest form.
nonisolated enum AdaptiveExpenditure {
    static let windowDays = 28
    static let minimumLoggedDays = 10

    static func estimate(days: [DayEnergy], weights: [WeightPoint], now: Date = .now, calendar: Calendar = .current) -> AdaptiveEstimate? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return nil }
        let window = days.filter { $0.date >= start && $0.date < today }
        // Days with very little logged are treated as not logged.
        let logged = window.filter { $0.intake >= 800 }
        guard logged.count >= minimumLoggedDays else { return nil }

        // The regression runs on the daily weigh-ins rather than the smoothed
        // trend: over four weeks it averages out the noise without the lag a
        // moving average adds.
        let daily = WeightTrend.daily(weights, calendar: calendar)
        guard let slope = WeightTrend.slopePerDay(daily, lastDays: windowDays, now: now) else { return nil }

        let averageIntake = logged.map(\.intake).reduce(0, +) / Double(logged.count)
        let averageExercise = window.isEmpty ? 0 : window.map(\.exercise).reduce(0, +) / Double(window.count)
        let tdee = averageIntake - slope * EnergyCalculator.kcalPerKilogram
        let baseline = tdee - averageExercise

        let recentWeighIns = daily.filter { $0.date >= start }.count
        let loggingConfidence = min(1, Double(logged.count) / 21)
        let weighInConfidence = min(1, Double(recentWeighIns) / 8)
        return AdaptiveEstimate(
            tdee: tdee.rounded(),
            baseline: baseline.rounded(),
            confidence: loggingConfidence * weighInConfidence,
            loggedDays: logged.count
        )
    }
}
