import Foundation

/// Calories and macronutrients for one food or one day.
nonisolated struct Nutrients: Hashable, Sendable, Codable {
    var kcal: Double
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = Nutrients(kcal: 0)

    /// Calories implied by the macros, using 4 kcal/g for protein and
    /// carbohydrates and 9 kcal/g for fat.
    var kcalFromMacros: Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    var hasMacros: Bool {
        protein > 0 || carbs > 0 || fat > 0
    }

    func scaled(by factor: Double) -> Nutrients {
        Nutrients(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }
}

extension Sequence where Element == Nutrients {
    nonisolated func total() -> Nutrients {
        reduce(.zero, +)
    }
}

nonisolated enum NumberInput {
    /// Parses a number typed by the user, accepting a comma or a dot as the
    /// decimal separator. Empty or negative text is nil.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Text for a text field: whole numbers without decimals.
    static func text(_ value: Double) -> String {
        guard value > 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}
