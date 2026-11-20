import Foundation
import Observation

/// Today's meals and totals, loaded from the Health app.
@Observable
final class FoodModel {
    static let shared = FoodModel()

    private let health = NutritionStore.shared
    private var started = false

    private(set) var entries: [FoodEntry] = []
    /// Calories eaten today from every app that writes to Health.
    private(set) var eaten: Double = 0
    /// Active calories burned today, as written by WHOOP or a watch.
    private(set) var burned: Double = 0
    private(set) var access: HealthAccess = .notDetermined
    var errorMessage: String?

    /// Totals of the meals logged in this app today.
    var ownTotals: Nutrients {
        entries.map(\.nutrients).total()
    }

    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        await requestAccess()
        health.observeChanges {
            Task { @MainActor in await FoodModel.shared.refresh() }
        }
    }

    func requestAccess() async {
        do {
            try await health.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func refresh() async {
        access = health.access
        guard access != .unavailable else { return }
        let today = Date.now
        do {
            entries = try await health.meals(on: today)
        } catch {
            entries = []
        }
        eaten = await health.caloriesEaten(on: today)
        burned = await health.activeCalories(on: today)
    }

    func log(name: String, nutrients: Nutrients, date: Date = .now) async {
        do {
            try await health.log(name: name, nutrients: nutrients, date: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func delete(_ entry: FoodEntry) async {
        do {
            try await health.delete(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
