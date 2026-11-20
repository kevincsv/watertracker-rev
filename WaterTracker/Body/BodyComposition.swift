import Foundation

/// What the composition estimates need besides the scale.
nonisolated struct BodyProfile: Sendable, Equatable {
    var sex: BodySex?
    var heightMeters: Double?
    var age: Int?
}

/// Body fat bands from the American Council on Exercise.
nonisolated enum FatBand: String, Sendable, CaseIterable {
    case essential
    case athletic
    case fit
    case average
    case high

    /// Upper limits of each band in percent, excluding `high`.
    static func limits(for sex: BodySex?) -> [Double] {
        switch sex {
        case .female?: [13, 20, 24, 31]
        case .male?: [5, 13, 17, 24]
        case nil: [9, 16.5, 20.5, 27.5]
        }
    }

    static func band(percent: Double, sex: BodySex?) -> FatBand {
        let limits = limits(for: sex)
        let bands: [FatBand] = [.essential, .athletic, .fit, .average]
        for (band, limit) in zip(bands, limits) where percent <= limit {
            return band
        }
        return .high
    }
}

/// What the fat and lean trends say about the last weeks.
nonisolated enum BodyChange: Sendable, Equatable {
    /// Losing fat while keeping or gaining lean mass.
    case recomposition
    /// Losing fat and some lean mass too.
    case cutting
    /// Losing mostly lean mass.
    case losingLean
    /// Gaining lean mass with little fat.
    case leanGain
    /// Gaining lean mass and fat.
    case bulking
    /// Gaining mostly fat.
    case gainingFat
    case stable
}

/// Body composition maths. Bioimpedance scales estimate fat from how easily a
/// tiny current crosses the body, which shifts with hydration, so everything
/// here works on trends rather than single readings.
nonisolated enum BodyComposition {
    /// Deurenberg et al. (1991): body fat from BMI, age and sex. Used only
    /// when the scale gives no fat reading. Typical error is about 4 points.
    static func estimatedFatPercent(bmi: Double, age: Int?, sex: BodySex?) -> Double {
        let sexTerm: Double = switch sex {
        case .male?: 1
        case .female?: 0
        case nil: 0.5
        }
        let value = 1.2 * bmi + 0.23 * Double(age ?? 35) - 10.8 * sexTerm - 5.4
        return min(max(value, 3), 60)
    }

    /// Fat-free mass index, scaled to a height of 1.80 m (Kouri et al. 1995)
    /// so it compares people of different heights. About 18 to 20 is typical
    /// for men who train and 15 to 17 for women; above 25 is rare without
    /// drugs.
    static func normalizedFFMI(leanKilograms: Double, heightMeters: Double) -> Double {
        let ffmi = leanKilograms / (heightMeters * heightMeters)
        return ffmi + 6.1 * (1.8 - heightMeters)
    }

    /// Classifies the last weeks from the weekly change in fat and lean mass
    /// (kg/week). Changes under `deadband` count as no change; the trend of
    /// a home scale cannot see smaller ones over a month.
    static func change(fatPerWeek: Double, leanPerWeek: Double, deadband: Double = 0.1) -> BodyChange {
        let fat = abs(fatPerWeek) < deadband ? 0 : fatPerWeek
        let lean = abs(leanPerWeek) < deadband ? 0 : leanPerWeek
        if fat == 0 && lean == 0 { return .stable }
        if fat < 0 {
            if lean >= 0 { return .recomposition }
            return -lean > -fat ? .losingLean : .cutting
        }
        if fat == 0 {
            return lean > 0 ? .leanGain : .losingLean
        }
        // Gaining fat.
        if lean > 0 { return lean >= fat ? .leanGain : .bulking }
        return .gainingFat
    }

    /// The shape of the 3D figure for a weight, height and composition.
    static func shape(weight: Double?, fatPercent: Double?, leanKilograms: Double?, profile: BodyProfile) -> BodyShape {
        let height = profile.heightMeters ?? (profile.sex == .female ? 1.63 : 1.76)
        var shape = BodyShape(heightMeters: height, sex: profile.sex)
        guard let weight, weight > 20 else { return shape }

        let bmi = weight / (height * height)
        let fat = fatPercent ?? estimatedFatPercent(bmi: bmi, age: profile.age, sex: profile.sex)
        let lean = leanKilograms ?? weight * (1 - fat / 100)
        let ffmi = normalizedFFMI(leanKilograms: lean, heightMeters: height)

        // 0 is an average build. Fat: about one step per 8 points of body fat
        // away from a typical value. Muscle: one step per 2.5 FFMI points.
        let referenceFat: Double = profile.sex == .female ? 25 : (profile.sex == .male ? 17 : 21)
        let referenceFFMI: Double = profile.sex == .female ? 15.5 : (profile.sex == .male ? 19 : 17.3)
        shape.fat = Float(min(max((fat - referenceFat) / 8, -1.2), 3))
        shape.muscle = Float(min(max((ffmi - referenceFFMI) / 2.5, -1.2), 2.5))
        return shape
    }
}

/// Parameters of the 3D figure. `fat` and `muscle` are 0 for an average build,
/// negative for leaner or less muscular and positive for more.
nonisolated struct BodyShape: Sendable, Equatable {
    var heightMeters: Double
    var sex: BodySex?
    var fat: Float = 0
    var muscle: Float = 0
}
