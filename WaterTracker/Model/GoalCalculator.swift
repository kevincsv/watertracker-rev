import Foundation

nonisolated enum BodySex: String, Sendable, CaseIterable {
    case female
    case male
}

nonisolated enum ReproductiveStatus: String, Sendable, CaseIterable {
    case none
    case pregnant
    case lactating
}

nonisolated enum CyclePhase: Sendable, Equatable {
    /// Bleeding logged today or yesterday.
    case menstruation
    /// The roughly two weeks between ovulation and the next period.
    case luteal
    case other
}

/// Everything the automatic goal depends on. Values come from Apple Health or
/// from what the user typed in Settings.
nonisolated struct GoalInputs: Sendable, Equatable {
    var sex: BodySex?
    var weightKilograms: Double?
    /// Minutes of workouts today, with overlapping workouts counted once.
    var workoutMinutes: Double = 0
    var hotWeather = false
    var status: ReproductiveStatus = .none
    var cyclePhase: CyclePhase?
}

/// The goal and the reasons behind it, so Settings can show where each
/// milliliter comes from.
nonisolated struct GoalBreakdown: Sendable, Equatable {
    enum Reason: Sendable, Equatable, Hashable {
        case body
        case activity
        case heat
        case pregnancy
        case lactation
        case menstruation
        case luteal
    }

    struct Item: Sendable, Equatable, Identifiable {
        let reason: Reason
        let milliliters: Double
        var id: Reason { reason }
    }

    let items: [Item]
    let total: Double
}

/// Works out a daily drinking goal. All numbers are public guidance turned
/// into simple rules; it is a sensible target, not medical advice.
///
/// - Body: 31 ml per kg for women, 35 for men, 33 if unknown (the usual
///   30 to 35 ml/kg range). Without a weight it falls back to the EFSA
///   reference of 2.0 L for women and 2.5 L for men.
/// - Exercise: about 0.5 L per hour of workouts, up to 1.5 L.
/// - Heat: 0.5 L.
/// - Pregnancy +0.3 L and breastfeeding +0.7 L (EFSA).
/// - Cycle: +0.25 L on period days and +0.2 L in the luteal phase, when body
///   temperature is higher. The evidence for this one is thin, so it is small.
nonisolated enum GoalCalculator {
    static let roundingStep = 50.0
    static let range: ClosedRange<Double> = 1000...6000

    static func goal(for inputs: GoalInputs) -> GoalBreakdown {
        var items: [GoalBreakdown.Item] = []
        func add(_ reason: GoalBreakdown.Reason, _ milliliters: Double) {
            if milliliters > 0 { items.append(.init(reason: reason, milliliters: milliliters)) }
        }

        add(.body, base(sex: inputs.sex, weightKilograms: inputs.weightKilograms))
        add(.activity, min(max(inputs.workoutMinutes, 0) * 500 / 60, 1500))
        if inputs.hotWeather { add(.heat, 500) }

        if inputs.sex != .male {
            switch inputs.status {
            case .pregnant: add(.pregnancy, 300)
            case .lactating: add(.lactation, 700)
            case .none: break
            }
            switch inputs.cyclePhase {
            case .menstruation?: add(.menstruation, 250)
            case .luteal?: add(.luteal, 200)
            case .other?, nil: break
            }
        }

        let sum = items.reduce(0) { $0 + $1.milliliters }
        let rounded = (sum / roundingStep).rounded() * roundingStep
        return GoalBreakdown(items: items, total: min(max(rounded, range.lowerBound), range.upperBound))
    }

    static func base(sex: BodySex?, weightKilograms: Double?) -> Double {
        if let weight = weightKilograms, weight > 0 {
            let perKilogram: Double = switch sex {
            case .female: 31
            case .male: 35
            case nil: 33
            }
            return min(max(weight, 30), 250) * perKilogram
        }
        return switch sex {
        case .female: 2000
        case .male: 2500
        case nil: 2250
        }
    }

    /// Total minutes covered by the given workouts, counting overlaps once
    /// (for example when a WHOOP strap and an iPhone record the same run).
    static func workoutMinutes(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in sorted {
            if let open = current, interval.start <= open.end {
                current = DateInterval(start: open.start, end: max(open.end, interval.end))
            } else {
                if let open = current { total += open.duration }
                current = interval
            }
        }
        if let open = current { total += open.duration }
        return total / 60
    }

    /// Estimates where today falls in the menstrual cycle from the days with
    /// bleeding logged in Apple Health. Returns nil when there is too little
    /// data to say.
    static func cyclePhase(bleedingDays: [Date], today: Date, calendar: Calendar = .current) -> CyclePhase? {
        let days = Set(bleedingDays.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return nil }
        if days.contains(todayStart) || days.contains(yesterday) { return .menstruation }

        // A period starts on a bleeding day whose previous day had none.
        let starts = days.filter { day in
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
            return !days.contains(previous) && day <= todayStart
        }.sorted()
        guard let lastStart = starts.last,
              let daysSince = calendar.dateComponents([.day], from: lastStart, to: todayStart).day
        else { return nil }

        // Use the user's own average cycle when there are at least two
        // cycles, else the textbook 28 days. Only plausible cycles count.
        let lengths = zip(starts, starts.dropFirst()).compactMap { pair -> Int? in
            guard let length = calendar.dateComponents([.day], from: pair.0, to: pair.1).day,
                  (21...45).contains(length) else { return nil }
            return length
        }
        let cycleLength = lengths.isEmpty ? 28 : lengths.reduce(0, +) / lengths.count

        // Past the expected next period by more than a week: data is stale.
        guard daysSince <= cycleLength + 7 else { return nil }
        return daysSince >= cycleLength - 14 ? .luteal : .other
    }
}
