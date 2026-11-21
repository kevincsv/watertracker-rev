import Foundation
import SwiftData

/// The local database for saved meals, recipes, routines and workouts.
nonisolated enum FoodStore {
    static var models: [any PersistentModel.Type] {
        [SavedFood.self, Routine.self, WorkoutSession.self, WorkoutSet.self]
    }

    /// Kept on this device only. The app has an iCloud entitlement for the
    /// friends feature, and SwiftData would otherwise sync to it by default.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration("Food", cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // The database on disk cannot be opened (damaged, or left by a build
        // with a different model). Rather than close on every launch, set it
        // aside and start a new one. Meals are in the Health app, so only
        // saved foods, routines and the workout log start again.
        setAside(configuration.url)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // Last resort: work from memory for this launch.
        let memory = ModelConfiguration("Food", isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: memory)
        } catch {
            fatalError("Could not open the food database: \(error)")
        }
    }

    /// Renames the database files so a new database can take their place.
    /// One earlier copy is kept, in case it is ever needed.
    private static func setAside(_ url: URL) {
        let files = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let current = URL(fileURLWithPath: url.path + suffix)
            let backup = URL(fileURLWithPath: url.path + ".unreadable" + suffix)
            try? files.removeItem(at: backup)
            try? files.moveItem(at: current, to: backup)
        }
    }
}
