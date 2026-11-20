import Foundation
import SwiftData

/// A saved list of exercises to start a workout from.
@Model
final class Routine {
    var name: String = ""
    var exercises: [String] = []
    var createdAt: Date = Date.now

    init(name: String, exercises: [String] = []) {
        self.name = name
        self.exercises = exercises
    }
}

/// One gym session.
@Model
final class WorkoutSession {
    var date: Date = Date.now
    var title: String = ""
    var notes: String = ""
    /// Exercise names in the order they are shown.
    var exercises: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
    var sets: [WorkoutSet] = []

    init(title: String, exercises: [String] = [], date: Date = .now) {
        self.title = title
        self.exercises = exercises
        self.date = date
    }

    func sets(for exercise: String) -> [WorkoutSet] {
        sets.filter { $0.exercise == exercise }.sorted { $0.order < $1.order }
    }
}

/// One set: an exercise, repetitions and weight.
@Model
final class WorkoutSet {
    var exercise: String = ""
    var reps: Int = 0
    var weightKg: Double = 0
    var order: Int = 0
    var session: WorkoutSession?

    init(exercise: String, reps: Int, weightKg: Double, order: Int) {
        self.exercise = exercise
        self.reps = reps
        self.weightKg = weightKg
        self.order = order
    }

    var record: SetRecord {
        SetRecord(exercise: exercise, reps: reps, weightKg: weightKg, order: order, sessionDate: session?.date ?? .distantPast)
    }
}
