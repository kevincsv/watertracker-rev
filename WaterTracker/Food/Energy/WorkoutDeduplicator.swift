import Foundation

/// A workout from the Health app.
nonisolated struct WorkoutRecord: Hashable, Sendable, Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let kcal: Double
    let activity: String
    let source: String

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
}

/// WHOOP, an Apple Watch and other apps often record the same session.
/// Workouts that overlap by at least half of the shorter one are treated as
/// the same session, and only the one with the most calories counts.
nonisolated enum WorkoutDeduplicator {
    static let overlapThreshold = 0.5

    static func overlaps(_ a: WorkoutRecord, _ b: WorkoutRecord) -> Bool {
        let shared = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard shared > 0 else { return false }
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return true }
        return shared / shorter >= overlapThreshold
    }

    static func deduplicate(_ records: [WorkoutRecord]) -> (kept: [WorkoutRecord], duplicates: [WorkoutRecord]) {
        var clusters: [[WorkoutRecord]] = []
        for record in records.sorted(by: { $0.start < $1.start }) {
            if let index = clusters.firstIndex(where: { cluster in cluster.contains { overlaps($0, record) } }) {
                clusters[index].append(record)
            } else {
                clusters.append([record])
            }
        }
        var kept: [WorkoutRecord] = []
        var duplicates: [WorkoutRecord] = []
        for cluster in clusters {
            let best = cluster.max { lhs, rhs in
                lhs.kcal == rhs.kcal ? lhs.duration < rhs.duration : lhs.kcal < rhs.kcal
            }!
            kept.append(best)
            duplicates.append(contentsOf: cluster.filter { $0.id != best.id })
        }
        return (kept.sorted { $0.start < $1.start }, duplicates)
    }

    static func totalCalories(_ records: [WorkoutRecord]) -> Double {
        deduplicate(records).kept.map(\.kcal).reduce(0, +)
    }
}
