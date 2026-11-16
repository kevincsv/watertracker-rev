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
