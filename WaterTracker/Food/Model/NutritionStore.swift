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
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let heightType = HKQuantityType(.height)

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
        var read: Set<HKObjectType> = nutritionTypes.union([activeType, bodyMassType, heightType])
        read.insert(HKObjectType.workoutType())
        read.insert(HKCharacteristicType(.dateOfBirth))
        read.insert(HKCharacteristicType(.biologicalSex))
        try await store.requestAuthorization(
            toShare: nutritionTypes.union([bodyMassType]),
            read: read
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

    /// Calls `handler` whenever calories eaten, workouts or weight change in
    /// Health, including changes made by other apps (for example WHOOP
    /// uploading a workout later).
    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: [HKSampleType] = [energyType, HKObjectType.workoutType(), bodyMassType]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                handler()
                completion()
            }
            store.execute(query)
        }
    }

    // MARK: Profile, weight and workouts

    func dateOfBirth() -> DateComponents? {
        try? store.dateOfBirthComponents()
    }

    func latestHeightCentimeters() async -> Double? {
        await latest(heightType)?.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// Weigh-ins from the last `days` days, oldest first.
    func weights(lastDays days: Int, now: Date = .now) async -> [WeightPoint] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType, predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { WeightPoint(date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    func logWeight(kilograms: Double, date: Date = .now) async throws {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        try await store.save(HKQuantitySample(type: bodyMassType, quantity: quantity, start: date, end: date))
    }

    /// Workouts from every app that started in the interval, duplicates included.
    func workouts(from start: Date, to end: Date) async -> [WorkoutRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        let activeType = self.activeType
        return workouts.map { workout in
            let kcal = workout.statistics(for: activeType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return WorkoutRecord(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                kcal: kcal,
                activity: WorkoutNames.name(for: workout.workoutActivityType),
                source: workout.sourceRevision.source.name
            )
        }
    }

    /// Calories eaten per day for the last `days` days before today, oldest first.
    func dailyIntake(lastDays days: Int, now: Date = .now, calendar: Calendar = .current) async -> [Date: Double] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return [:] }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: energyType, predicate: HKQuery.predicateForSamples(withStart: start, end: today)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: today) { statistics, _ in
            totals[statistics.startDate] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        }
        return totals
    }

    private func latest(_ type: HKQuantityType) async -> HKQuantitySample? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        return try? await descriptor.result(for: store).first
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
