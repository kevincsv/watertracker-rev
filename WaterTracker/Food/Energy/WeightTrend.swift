import Foundation

nonisolated struct WeightPoint: Hashable, Sendable, Identifiable {
    let date: Date
    let kilograms: Double
    var id: Date { date }
}

/// A smoothed weight trend that ignores day-to-day water swings
/// (exponential moving average with about a ten-day memory).
nonisolated enum WeightTrend {
    static let smoothing = 0.1

    /// One value per day: the average of that day's weigh-ins.
    static func daily(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        let groups = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
        return groups.map { day, items in
            WeightPoint(date: day, kilograms: items.map(\.kilograms).reduce(0, +) / Double(items.count))
        }
        .sorted { $0.date < $1.date }
    }

    /// The trend at each weigh-in day. Gaps between weigh-ins count as
    /// several days of smoothing, so a late weigh-in pulls harder.
    static func trend(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        let days = daily(points, calendar: calendar)
        guard var current = days.first?.kilograms, let firstDate = days.first?.date else { return [] }
        var previous = firstDate
        var result: [WeightPoint] = []
        for point in days {
            let elapsed = max(1, calendar.dateComponents([.day], from: previous, to: point.date).day ?? 1)
            let factor = 1 - pow(1 - smoothing, Double(elapsed))
            if point.date != firstDate {
                current += factor * (point.kilograms - current)
            }
            result.append(WeightPoint(date: point.date, kilograms: current))
            previous = point.date
        }
        return result
    }

    /// Least-squares slope, in kilograms per day, over the points from the
    /// last `days` days. Nil with fewer than two points or
    /// less than a week of data.
    static func slopePerDay(_ points: [WeightPoint], lastDays days: Int = 28, now: Date = .now) -> Double? {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let recent = points.filter { $0.date >= start }
        guard recent.count >= 2, let first = recent.first?.date, let last = recent.last?.date,
              last.timeIntervalSince(first) >= 7 * 86_400
        else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = recent.map(\.kilograms)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
