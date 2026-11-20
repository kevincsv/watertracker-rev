import Foundation

/// One reading with the smoothed trend at that moment.
nonisolated struct TrendPoint: Sendable, Hashable, Identifiable {
    var date: Date
    var raw: Double
    var trend: Double
    /// Readings far from the trend that the next reading did not confirm
    /// (a scale on carpet, wet feet, a heavy meal). They are drawn but do not
    /// move the trend.
    var isOutlier: Bool

    var id: Date { date }
}

/// Smooths noisy scale readings into a trend.
///
/// - Exponential smoothing on real time, not on reading count: each reading
///   pulls the trend by `1 - 2^(-days / halfLife)`, so a reading after a week
///   away counts far more than the third reading of the same morning, and gaps
///   of any length work.
/// - Robust: a reading more than `threshold` times the running typical error
///   from the trend is held back. If the next reading lands on the same side,
///   the change is real and both are used; if not, it is marked an outlier.
/// - The first reading starts the trend, and the first few readings move it
///   faster (the half-life ramps up) so it does not lag behind a new user.
nonisolated enum BodyTrend {
    static let halfLifeDays = 7.0
    static let threshold = 3.5

    static func smooth(
        _ samples: [BodySample],
        noise: Double,
        halfLifeDays: Double = BodyTrend.halfLifeDays,
        threshold: Double = BodyTrend.threshold
    ) -> [TrendPoint] {
        let samples = samples.sorted { $0.date < $1.date }
        guard let first = samples.first else { return [] }

        var points = [TrendPoint(date: first.date, raw: first.value, trend: first.value, isOutlier: false)]
        var trend = first.value
        var lastDate = first.date
        var typicalError = noise
        var held: Int?
        var used = 1

        func accept(_ date: Date, _ value: Double) {
            let days = max(date.timeIntervalSince(lastDate) / 86_400, 0)
            // Warm-up: the second reading counts as if it came a full
            // half-life later, the third as if half of one, and so on.
            let warmUpDays = used < 5 ? halfLifeDays / Double(used) : 0
            let alpha = 1 - pow(2, -max(days, warmUpDays) / halfLifeDays)
            let residual = value - trend
            trend += alpha * residual
            typicalError += 0.15 * (abs(residual) - typicalError)
            typicalError = max(typicalError, noise / 2)
            lastDate = date
            used += 1
        }

        for sample in samples.dropFirst() {
            let residual = sample.value - trend
            let isFar = abs(residual) > threshold * typicalError
            if let index = held {
                held = nil
                if isFar, (points[index].raw - trend).sign == residual.sign {
                    // Two in a row on the same side: the change is real.
                    accept(points[index].date, points[index].raw)
                    points[index].isOutlier = false
                    points[index].trend = trend
                    accept(sample.date, sample.value)
                    points.append(TrendPoint(date: sample.date, raw: sample.value, trend: trend, isOutlier: false))
                    continue
                }
            }
            if isFar {
                points.append(TrendPoint(date: sample.date, raw: sample.value, trend: trend, isOutlier: true))
                held = points.count - 1
                continue
            }
            accept(sample.date, sample.value)
            points.append(TrendPoint(date: sample.date, raw: sample.value, trend: trend, isOutlier: false))
        }
        return points
    }

    /// The trend at any date: interpolated between readings, held flat after
    /// the last one, nil before the first.
    static func value(at date: Date, in points: [TrendPoint]) -> Double? {
        guard let first = points.first, date >= first.date else { return nil }
        guard let afterIndex = points.firstIndex(where: { $0.date > date }) else { return points.last?.trend }
        let after = points[afterIndex]
        let before = points[afterIndex - 1]
        let span = after.date.timeIntervalSince(before.date)
        guard span > 0 else { return after.trend }
        let fraction = date.timeIntervalSince(before.date) / span
        return before.trend + (after.trend - before.trend) * fraction
    }

    /// Change per week over the last `days` days, by least squares on the
    /// trend. Nil without at least three readings spanning a week.
    static func weeklyRate(_ points: [TrendPoint], days: Double = 28, now: Date = .now) -> Double? {
        let start = now.addingTimeInterval(-days * 86_400)
        let recent = points.filter { $0.date >= start && $0.date <= now && !$0.isOutlier }
        guard recent.count >= 3,
              let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 6 * 86_400
        else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map(\.trend)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator * 7
    }
}
