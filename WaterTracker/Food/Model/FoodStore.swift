import SwiftData

/// The local database for saved meals, recipes, routines and workouts.
nonisolated enum FoodStore {
    static var models: [any PersistentModel.Type] {
        [SavedFood.self, Routine.self, WorkoutSession.self, WorkoutSet.self]
    }

    /// Kept on this device only. The app has an iCloud entitlement for the
    /// friends feature, and SwiftData would otherwise sync to it by default.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration("Food", cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            fatalError("Could not open the food database: \(error)")
        }
    }
}
