import Foundation
import Observation

/// Settings for the calorie target that the water goal does not already
/// have. Sex, pregnancy and a typed weight come from `AppSettings`, so they
/// are only asked once.
@Observable
final class FoodProfileSettings {
    static let shared = FoodProfileSettings()

    @ObservationIgnored private let defaults: UserDefaults

    /// Work out the daily target instead of using a fixed number.
    var autoTarget: Bool { didSet { defaults.set(autoTarget, forKey: Key.autoTarget) } }
    /// Correct the formula with the real weight trend and intake.
    var adaptive: Bool { didSet { defaults.set(adaptive, forKey: Key.adaptive) } }
    /// 0 means "use the Health app".
    var birthYear: Int { didSet { defaults.set(birthYear, forKey: Key.birthYear) } }
    /// 0 means "use the Health app".
    var heightCm: Double { didSet { defaults.set(heightCm, forKey: Key.heightCm) } }
    var activity: ActivityLevel { didSet { defaults.set(activity.rawValue, forKey: Key.activity) } }
    var goal: WeightGoal { didSet { defaults.set(goal.rawValue, forKey: Key.goal) } }
    var weeklyRateKg: Double { didSet { defaults.set(weeklyRateKg, forKey: Key.weeklyRate) } }

    private enum Key {
        static let autoTarget = "food.autoTarget"
        static let adaptive = "food.adaptive"
        static let birthYear = "food.birthYear"
        static let heightCm = "food.heightCm"
        static let activity = "food.activity"
        static let goal = "food.goal"
        static let weeklyRate = "food.weeklyRateKg"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.autoTarget: true, Key.adaptive: true, Key.weeklyRate: 0.5])
        autoTarget = defaults.bool(forKey: Key.autoTarget)
        adaptive = defaults.bool(forKey: Key.adaptive)
        birthYear = defaults.integer(forKey: Key.birthYear)
        heightCm = defaults.double(forKey: Key.heightCm)
        activity = defaults.string(forKey: Key.activity).flatMap(ActivityLevel.init(rawValue:)) ?? .light
        goal = defaults.string(forKey: Key.goal).flatMap(WeightGoal.init(rawValue:)) ?? .maintain
        weeklyRateKg = defaults.double(forKey: Key.weeklyRate)
    }
}
