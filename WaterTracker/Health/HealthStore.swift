import Foundation
import HealthKit

/// One water sample from Apple Health.
nonisolated struct WaterEntry: Identifiable, Sendable, Hashable {
    let id: UUID
    let date: Date
    let milliliters: Double
    /// Only samples written by this app can be deleted by it.
    let isOwn: Bool
}

/// Total water for one calendar day.
nonisolated struct DayTotal: Identifiable, Sendable, Hashable {
    let date: Date
    let milliliters: Double
    var id: Date { date }
}

nonisolated enum HealthAccess: Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

/// Thin async wrapper around HealthKit. Apple Health is the only place water
/// intake is stored; this app keeps no copy of its own.
nonisolated final class HealthStore: Sendable {
    static let shared = HealthStore()

    private let store = HKHealthStore()
    private let waterType = HKQuantityType(.dietaryWater)
    private let unit = HKUnit.literUnit(with: .milli)

    var access: HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch store.authorizationStatus(for: waterType) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [waterType], read: [waterType])
    }

    @discardableResult
    func log(milliliters: Double, date: Date = .now) async throws -> WaterEntry {
        let quantity = HKQuantity(unit: unit, doubleValue: milliliters)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
        return WaterEntry(id: sample.uuid, date: date, milliliters: milliliters, isOwn: true)
    }

    func delete(_ entry: WaterEntry) async throws {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: waterType, predicate: HKQuery.predicateForObject(with: entry.id))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        guard let sample = samples.first else { return }
        try await store.delete(sample)
    }

    /// Samples for one day, newest first.
    func entries(on day: Date, calendar: Calendar = .current) async throws -> [WaterEntry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: waterType, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let ownBundle = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store).map { sample in
            WaterEntry(
                id: sample.uuid,
                date: sample.startDate,
                milliliters: sample.quantity.doubleValue(for: unit),
                isOwn: sample.sourceRevision.source.bundleIdentifier == ownBundle
            )
        }
    }

    /// Daily totals for the last `days` days, oldest first, ending today.
    func dailyTotals(days: Int, now: Date = .now, calendar: Calendar = .current) async throws -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today)
        else { return [] }

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: waterType, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        let unit = self.unit
        var totals: [DayTotal] = []
        collection.enumerateStatistics(from: start, to: today) { statistics, _ in
            let value = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
            totals.append(DayTotal(date: statistics.startDate, milliliters: value))
        }
        return totals
    }

    // MARK: Data for the automatic goal (read only)

    /// Asks to read what the automatic goal uses. Only called once the user
    /// turns that goal on, and the cycle only when they turn its adjustment on.
    /// The app never writes any of these.
    func requestGoalAuthorization(includeCycle: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = [
            HKCharacteristicType(.biologicalSex),
            HKQuantityType(.bodyMass),
            HKObjectType.workoutType(),
            HKCategoryType(.pregnancy),
            HKCategoryType(.lactation),
        ]
        if includeCycle {
            read.insert(HKCategoryType(.menstrualFlow))
        }
        try await store.requestAuthorization(toShare: [], read: read)
    }

    /// Female or male as set in the Health profile, or nil.
    func biologicalSex() -> BodySex? {
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female?: .female
        case .male?: .male
        default: nil
        }
    }

    /// The most recent weight in Apple Health, in kilograms.
    func latestWeightKilograms() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let sample = try? await descriptor.result(for: store).first
        return sample?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    /// Today's workouts from every source (iPhone, Apple Watch, WHOOP...).
    func workoutIntervals(on day: Date, calendar: Calendar = .current) async -> [DateInterval] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        return workouts.compactMap { workout in
            // Only the part of the workout that falls on this day.
            let from = max(workout.startDate, start)
            let to = min(workout.endDate, end)
            return to > from ? DateInterval(start: from, end: to) : nil
        }
    }

    /// Pregnancy or breastfeeding logged in Apple Health for right now.
    func reproductiveStatus(now: Date = .now) async -> ReproductiveStatus {
        func isActive(_ identifier: HKCategoryTypeIdentifier) async -> Bool {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(
                    type: HKCategoryType(identifier),
                    predicate: HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-60), end: now)
                )],
                sortDescriptors: [],
                limit: 1
            )
            return !((try? await descriptor.result(for: store)) ?? []).isEmpty
        }
        if await isActive(.lactation) { return .lactating }
        if await isActive(.pregnancy) { return .pregnant }
        return .none
    }

    /// Days with bleeding logged in the last `days` days.
    func bleedingDays(lastDays days: Int = 120, now: Date = .now) async -> [Date] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.menstrualFlow),
                predicate: HKQuery.predicateForSamples(withStart: start, end: now)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples
            .filter { $0.value != HKCategoryValueVaginalBleeding.none.rawValue }
            .map(\.startDate)
    }

    /// Calls `handler` whenever water data changes in Apple Health, including
    /// changes made by other apps.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { _, completion, _ in
            handler()
            completion()
        }
        store.execute(query)
    }
}
