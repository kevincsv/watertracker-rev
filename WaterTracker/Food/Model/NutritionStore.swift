import Foundation
import HealthKit

/// Thin async wrapper around HealthKit. Meals are saved to the Health app as
/// food correlations (calories plus macros), which is what WHOOP and other
/// apps read. This app keeps no copy of its own.
nonisolated final class NutritionStore: Sendable {
    static let shared = NutritionStore()

    private let store = HKHealthStore()
    private let energyType = HKQuantityType(.dietaryEnergyConsumed)
    private let proteinType = HKQuantityType(.dietaryProtein)
    private let carbsType = HKQuantityType(.dietaryCarbohydrates)
    private let fatType = HKQuantityType(.dietaryFatTotal)
    private let activeType = HKQuantityType(.activeEnergyBurned)
    private let foodType = HKCorrelationType(.food)

    private var nutritionTypes: Set<HKQuantityType> {
        [energyType, proteinType, carbsType, fatType]
    }

    var access: HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(for: energyType) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Correlation types are not authorized directly: access to the
        // quantities inside them covers saving and reading meals.
        try await store.requestAuthorization(
            toShare: nutritionTypes,
            read: nutritionTypes.union([activeType])
        )
    }

    /// Saves one meal: calories always, and each macro that is above zero.
    func log(name: String, nutrients: Nutrients, date: Date = .now) async throws {
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        var samples: Set<HKSample> = []
        func add(_ type: HKQuantityType, _ value: Double, _ unit: HKUnit) {
            guard value > 0 else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            samples.insert(HKQuantitySample(type: type, quantity: quantity, start: date, end: date, metadata: metadata))
        }
        add(energyType, nutrients.kcal, .kilocalorie())
        add(proteinType, nutrients.protein, .gram())
        add(carbsType, nutrients.carbs, .gram())
        add(fatType, nutrients.fat, .gram())
        guard !samples.isEmpty else { return }

        let meal = HKCorrelation(type: foodType, start: date, end: date, objects: samples, metadata: metadata)
        try await store.save(meal)
    }

    /// Deletes a meal this app saved, together with the values inside it.
    func delete(_ entry: FoodEntry) async throws {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: foodType, predicate: HKQuery.predicateForObject(with: entry.id))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let meal = try await descriptor.result(for: store).first else { return }
        let contents = meal.objects.map { $0 as HKObject }
        if !contents.isEmpty {
            try await store.delete(contents)
        }
        // Deleting the contents can already remove the correlation.
        try? await store.delete(meal)
    }

    /// Meals this app saved on one day, newest first.
    func meals(on day: Date, calendar: Calendar = .current) async throws -> [FoodEntry] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            dayPredicate(day, calendar: calendar),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: foodType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try await descriptor.result(for: store).map(entry(from:))
    }

    /// Calories eaten on one day, from every app that writes to Health.
    func caloriesEaten(on day: Date, calendar: Calendar = .current) async -> Double {
        await sum(energyType, unit: .kilocalorie(), predicate: dayPredicate(day, calendar: calendar))
    }

    /// Active calories burned on one day, as written by WHOOP or a watch.
    func activeCalories(on day: Date, calendar: Calendar = .current) async -> Double {
        await sum(activeType, unit: .kilocalorie(), predicate: dayPredicate(day, calendar: calendar))
    }

    /// Calls `handler` whenever calories eaten change in Health, including
    /// changes made by other apps.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: energyType, predicate: nil) { _, completion, _ in
            handler()
            completion()
        }
        store.execute(query)
    }

    private func dayPredicate(_ day: Date, calendar: Calendar) -> NSPredicate {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return HKQuery.predicateForSamples(withStart: start, end: end)
    }

    private func sum(_ type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        // No data, or no permission to read it, both count as zero.
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func entry(from meal: HKCorrelation) -> FoodEntry {
        func total(_ type: HKQuantityType, _ unit: HKUnit) -> Double {
            meal.objects(for: type)
                .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
                .reduce(0, +)
        }
        return FoodEntry(
            id: meal.uuid,
            name: meal.metadata?[HKMetadataKeyFoodType] as? String ?? "",
            date: meal.startDate,
            nutrients: Nutrients(
                kcal: total(energyType, .kilocalorie()),
                protein: total(proteinType, .gram()),
                carbs: total(carbsType, .gram()),
                fat: total(fatType, .gram())
            )
        )
    }
}
