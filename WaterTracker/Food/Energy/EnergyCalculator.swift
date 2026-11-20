import Foundation

/// Daily activity outside of workouts. Workouts are added on top, from
/// the Health app, so these factors are lower than classic "activity
/// multipliers" that already include exercise.
nonisolated enum ActivityLevel: String, CaseIterable, Identifiable, Sendable {
    case sedentary
    case light
    case moderate
    case high

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.3
        case .moderate: 1.45
        case .high: 1.6
        }
    }
}

nonisolated enum WeightGoal: String, CaseIterable, Identifiable, Sendable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }
}

/// Everything the calorie target depends on.
nonisolated struct EnergyProfile: Sendable, Equatable {
    var sex: BodySex?
    var age: Int?
    var heightCm: Double?
    var weightKg: Double?
    var activity: ActivityLevel = .light
    var goal: WeightGoal = .maintain
    /// Kilograms per week to lose or gain.
    var weeklyRateKg: Double = 0.5
    var status: ReproductiveStatus = .none

    var isComplete: Bool {
        sex != nil && (age ?? 0) > 0 && (heightCm ?? 0) > 0 && (weightKg ?? 0) > 0
    }
}

/// How today's target was worked out, so the app can show it.
nonisolated struct EnergyTarget: Sendable, Equatable {
    /// Basal metabolic rate (Mifflin-St Jeor).
    var bmr: Double
    /// Daily burn without workouts, from the formula.
    var formulaBaseline: Double
    /// Daily burn without workouts, learned from weight and intake, if known.
    var adaptiveBaseline: Double?
    /// How much the learned value counts, 0...1.
    var adaptiveWeight: Double
    /// Daily burn without workouts actually used.
    var baseline: Double
    /// Workout calories today, without duplicates.
    var exercise: Double
    /// Negative to lose weight, positive to gain.
    var goalAdjustment: Double
    /// Extra for pregnancy or breastfeeding.
    var statusExtra: Double
    /// True when the target was raised to the safe minimum.
    var floorApplied: Bool
    var calories: Double
    var proteinGrams: Double
    var fatGrams: Double
    var carbGrams: Double

    var macros: Nutrients {
        Nutrients(kcal: calories, protein: proteinGrams, carbs: carbGrams, fat: fatGrams)
    }
}

nonisolated enum EnergyCalculator {
    /// Approximate energy in one kilogram of body weight change.
    static let kcalPerKilogram = 7700.0

    /// Mifflin-St Jeor resting energy, in kcal per day.
    static func bmr(sex: BodySex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// Lowest daily target the app will suggest.
    static func minimumCalories(sex: BodySex) -> Double {
        sex == .male ? 1500 : 1200
    }

    static func statusExtra(_ status: ReproductiveStatus) -> Double {
        switch status {
        case .none: 0
        case .pregnant: 300
        case .lactating: 400
        }
    }

    /// Today's target, or nil while the profile is incomplete.
    static func target(profile: EnergyProfile, exerciseToday: Double, adaptive: AdaptiveEstimate?) -> EnergyTarget? {
        guard profile.isComplete, let sex = profile.sex, let age = profile.age,
              let height = profile.heightCm, let weight = profile.weightKg
        else { return nil }

        let bmr = bmr(sex: sex, age: age, heightCm: height, weightKg: weight)
        let formulaBaseline = bmr * profile.activity.factor

        var adaptiveBaseline: Double?
        var adaptiveWeight = 0.0
        if let adaptive {
            // A learned value far from the formula usually means incomplete
            // logging, so it is kept within a plausible range.
            adaptiveBaseline = min(max(adaptive.baseline, formulaBaseline * 0.75), formulaBaseline * 1.35)
            adaptiveWeight = min(max(adaptive.confidence, 0), 1)
        }
        let baseline = formulaBaseline * (1 - adaptiveWeight) + (adaptiveBaseline ?? formulaBaseline) * adaptiveWeight

        let rate = min(max(profile.weeklyRateKg, 0), 1)
        let goalAdjustment: Double = switch profile.goal {
        case .lose: -rate * kcalPerKilogram / 7
        case .maintain: 0
        case .gain: rate * kcalPerKilogram / 7
        }
        let extra = statusExtra(profile.status)
        let exercise = max(exerciseToday, 0)

        var calories = baseline + exercise + goalAdjustment + extra
        let floor = minimumCalories(sex: sex)
        let floorApplied = calories < floor
        calories = max(calories, floor).rounded()

        // Protein for someone who trains: 1.8 g/kg (2.2 g/kg while losing),
        // fat 25 % of calories, carbohydrates the rest.
        let protein = (weight * (profile.goal == .lose ? 2.2 : 1.8)).rounded()
        let fat = (calories * 0.25 / 9).rounded()
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4).rounded()

        return EnergyTarget(
            bmr: bmr.rounded(),
            formulaBaseline: formulaBaseline.rounded(),
            adaptiveBaseline: adaptiveBaseline?.rounded(),
            adaptiveWeight: adaptiveWeight,
            baseline: baseline.rounded(),
            exercise: exercise.rounded(),
            goalAdjustment: goalAdjustment.rounded(),
            statusExtra: extra,
            floorApplied: floorApplied,
            calories: calories,
            proteinGrams: protein,
            fatGrams: fat,
            carbGrams: carbs
        )
    }

    /// Whole years between `birth` and `now`.
    static func age(birth: DateComponents, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let date = calendar.date(from: birth) else { return nil }
        return calendar.dateComponents([.year], from: date, to: now).year
    }
}
