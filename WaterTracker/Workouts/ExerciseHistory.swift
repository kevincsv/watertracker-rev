import Foundation

/// A plain copy of one set, so history logic can be tested without SwiftData.
nonisolated struct SetRecord: Hashable, Sendable {
    let exercise: String
    let reps: Int
    let weightKg: Double
    let order: Int
    let sessionDate: Date
}

nonisolated enum ExerciseHistory {
    /// Exercise names match ignoring case, accents and surrounding spaces.
    static func key(_ exercise: String) -> String {
        exercise.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The sets of `exercise` from the most recent session before `date`.
    static func lastSession(of exercise: String, in records: [SetRecord], before date: Date) -> [SetRecord] {
        let wanted = key(exercise)
        let earlier = records.filter { key($0.exercise) == wanted && $0.sessionDate < date }
        guard let latest = earlier.map(\.sessionDate).max() else { return [] }
        return earlier.filter { $0.sessionDate == latest }.sorted { $0.order < $1.order }
    }

    /// Estimated one-repetition maximum (Epley formula).
    static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// The heaviest estimated one-repetition maximum among `records`.
    static func bestOneRepMax(_ records: [SetRecord]) -> Double {
        records.map { estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
    }

    /// Short text such as "3 × 8 · 60 kg" or "8, 8, 6 reps · 60–65 kg".
    static func summary(_ records: [SetRecord], unit: WeightUnit) -> String {
        guard !records.isEmpty else { return "" }
        let reps = records.map(\.reps)
        let repsText = Set(reps).count == 1
            ? "\(records.count) × \(reps[0])"
            : reps.map(String.init).joined(separator: ", ") + " reps"
        let weights = records.map(\.weightKg).filter { $0 > 0 }
        guard let low = weights.min(), let high = weights.max() else { return repsText }
        if abs(high - low) < 0.01 {
            return "\(repsText) · \(unit.format(kilograms: low))"
        }
        let lowText = unit.fromKilograms(low).formatted(.number.precision(.fractionLength(0...1)))
        return "\(repsText) · \(lowText)–\(unit.format(kilograms: high))"
    }
}
