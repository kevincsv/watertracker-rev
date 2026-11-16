import Foundation

/// Display unit for water amounts. Everything is stored in milliliters; the
/// unit only affects how amounts are shown and which defaults are used.
nonisolated enum VolumeUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case milliliters = "ml"
    case fluidOunces = "oz"

    static let millilitersPerOunce = 29.5735

    var id: String { rawValue }
    var symbol: String { rawValue }

    func value(fromMilliliters ml: Double) -> Double {
        switch self {
        case .milliliters: ml
        case .fluidOunces: ml / Self.millilitersPerOunce
        }
    }

    func milliliters(from value: Double) -> Double {
        switch self {
        case .milliliters: value
        case .fluidOunces: value * Self.millilitersPerOunce
        }
    }

    /// "1,250 ml" or "42.5 oz".
    func format(_ ml: Double) -> String {
        switch self {
        case .milliliters:
            "\(Int(ml.rounded()).formatted()) ml"
        case .fluidOunces:
            "\(value(fromMilliliters: ml).formatted(.number.precision(.fractionLength(0...1)))) oz"
        }
    }

    var defaultGoal: Double { milliliters(from: self == .milliliters ? 2400 : 80) }

    var defaultQuickAmounts: [Double] {
        (self == .milliliters ? [250, 500, 750] : [8, 12, 16]).map { milliliters(from: $0) }
    }

    var goalStep: Double { milliliters(from: self == .milliliters ? 100 : 4) }
    var goalRange: ClosedRange<Double> {
        self == .milliliters ? 1000...6000 : milliliters(from: 32)...milliliters(from: 200)
    }

    var amountStep: Double { milliliters(from: self == .milliliters ? 50 : 1) }
    var amountRange: ClosedRange<Double> {
        self == .milliliters ? 50...2000 : milliliters(from: 1)...milliliters(from: 64)
    }
}
