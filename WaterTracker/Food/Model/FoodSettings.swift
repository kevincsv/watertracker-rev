import Foundation

/// Keys for the few settings, stored in the app's own UserDefaults.
nonisolated enum SettingsKey {
    static let dailyGoal = "food.dailyCalorieGoal"
    static let weightUnit = "workouts.weightUnit"
    static let defaultGoal = 2200
}

nonisolated enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case kg
    case lb

    static let poundsPerKilogram = 2.20462262185

    var id: String { rawValue }
    var symbol: String { rawValue }

    func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kg: kilograms
        case .lb: kilograms * Self.poundsPerKilogram
        }
    }

    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value / Self.poundsPerKilogram
        }
    }

    func format(kilograms: Double) -> String {
        let value = fromKilograms(kilograms)
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(symbol)"
    }
}
