import Foundation

/// Where a measurement came from.
nonisolated enum BodySource: String, Sendable, Codable, Hashable {
    /// The Health app (the Withings app, another scale or a manual entry).
    case health
    /// Read straight from the user's Withings account.
    case withings
}

/// Everything the body tab can show. Masses are in kilograms.
nonisolated enum BodyMetric: String, Sendable, CaseIterable, Identifiable, Codable {
    case weight
    case fatPercent
    case fatMass
    case leanMass
    case muscleMass
    case waterMass
    case boneMass
    case visceralFat
    case basalMetabolicRate
    case metabolicAge
    case bmi

    var id: String { rawValue }

    /// Typical day-to-day noise of one reading, used by the trend to tell a
    /// bad reading from a real change.
    var noise: Double {
        switch self {
        case .weight: 0.6
        case .fatPercent: 0.9
        case .fatMass: 0.8
        case .leanMass, .muscleMass: 0.7
        case .waterMass: 0.6
        case .boneMass: 0.08
        case .visceralFat: 0.7
        case .basalMetabolicRate: 25
        case .metabolicAge: 1.5
        case .bmi: 0.2
        }
    }

    /// Lower is better for these, so a falling trend is shown in green.
    var lowerIsBetter: Bool {
        switch self {
        case .fatPercent, .fatMass, .visceralFat, .metabolicAge: true
        default: false
        }
    }

    var isMass: Bool {
        switch self {
        case .weight, .fatMass, .leanMass, .muscleMass, .waterMass, .boneMass: true
        default: false
        }
    }
}

/// One weigh-in: whatever the scale measured at that moment. Readings from the
/// Health app and from Withings for the same weigh-in are merged into one.
nonisolated struct BodyReading: Sendable, Codable, Hashable, Identifiable {
    var date: Date
    var values: [BodyMetric: Double] = [:]
    var sources: Set<BodySource> = []

    var id: Date { date }

    subscript(metric: BodyMetric) -> Double? {
        get { values[metric] }
        set { values[metric] = newValue }
    }

    /// Fills in what can be worked out from the rest: fat mass from weight and
    /// fat percentage, lean mass from weight minus fat, and BMI from height.
    func completed(heightMeters: Double?) -> BodyReading {
        var reading = self
        if let weight = reading[.weight] {
            if reading[.fatMass] == nil, let percent = reading[.fatPercent] {
                reading[.fatMass] = weight * percent / 100
            }
            if reading[.fatPercent] == nil, let fat = reading[.fatMass], weight > 0 {
                reading[.fatPercent] = fat / weight * 100
            }
            if reading[.leanMass] == nil, let fat = reading[.fatMass] {
                reading[.leanMass] = weight - fat
            }
            if reading[.bmi] == nil, let height = heightMeters, height > 0.5 {
                reading[.bmi] = weight / (height * height)
            }
        }
        return reading
    }
}

/// A single timestamped value, the input of the trend.
nonisolated struct BodySample: Sendable, Hashable {
    var date: Date
    var value: Double
}

/// Merges readings taken within `window` seconds of each other into one
/// weigh-in. Withings values win over Health values, since the Withings
/// account has the scale's full precision. Oldest first.
nonisolated enum BodyMerge {
    static func merge(_ readings: [BodyReading], window: TimeInterval = 180) -> [BodyReading] {
        let sorted = readings.sorted { $0.date < $1.date }
        var merged: [BodyReading] = []
        for reading in sorted {
            if var last = merged.last, reading.date.timeIntervalSince(last.date) <= window {
                let preferNew = reading.sources.contains(.withings) && !last.sources.contains(.withings)
                for (metric, value) in reading.values where last[metric] == nil || preferNew {
                    last[metric] = value
                }
                last.sources.formUnion(reading.sources)
                merged[merged.count - 1] = last
            } else {
                merged.append(reading)
            }
        }
        return merged
    }

    static func samples(of metric: BodyMetric, in readings: [BodyReading]) -> [BodySample] {
        readings.compactMap { reading in
            reading[metric].map { BodySample(date: reading.date, value: $0) }
        }
    }
}
