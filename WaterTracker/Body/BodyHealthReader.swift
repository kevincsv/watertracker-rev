import Foundation
import HealthKit

/// Reads body measurements from the Health app. Read only: weigh-ins are
/// logged by the Withings app (or the Meals tab), never by this screen.
nonisolated final class BodyHealthReader: Sendable {
    static let shared = BodyHealthReader()

    private let store = HKHealthStore()

    private static var quantityTypes: [(HKQuantityTypeIdentifier, BodyMetric, HKUnit, Double)] {
        [
        (.bodyMass, .weight, .gramUnit(with: .kilo), 1),
        (.bodyFatPercentage, .fatPercent, .percent(), 100),
        (.leanBodyMass, .leanMass, .gramUnit(with: .kilo), 1),
        ]
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        var read: Set<HKObjectType> = [
            HKQuantityType(.height),
            HKCharacteristicType(.biologicalSex),
            HKCharacteristicType(.dateOfBirth),
        ]
        for (identifier, _, _, _) in Self.quantityTypes {
            read.insert(HKQuantityType(identifier))
        }
        try await store.requestAuthorization(toShare: [], read: read)
    }

    /// Weight, body fat and lean mass from the last `days` days, one reading
    /// per sample (merge them with `BodyMerge`).
    func readings(lastDays days: Int = 730, now: Date = .now) async -> [BodyReading] {
        guard isAvailable else { return [] }
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        var readings: [BodyReading] = []
        for (identifier, metric, unit, factor) in Self.quantityTypes {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = (try? await descriptor.result(for: store)) ?? []
            for sample in samples {
                var reading = BodyReading(date: sample.startDate, sources: [.health])
                reading[metric] = sample.quantity.doubleValue(for: unit) * factor
                readings.append(reading)
            }
        }
        return readings
    }

    func latestHeightMeters() async -> Double? {
        guard isAvailable else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.height))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let sample = try? await descriptor.result(for: store).first
        return sample?.quantity.doubleValue(for: .meter())
    }

    func biologicalSex() -> BodySex? {
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female?: .female
        case .male?: .male
        default: nil
        }
    }

    func age(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birth = calendar.date(from: components)
        else { return nil }
        return calendar.dateComponents([.year], from: birth, to: now).year
    }
}
