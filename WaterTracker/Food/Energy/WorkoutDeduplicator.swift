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

/// One real session: the workout that counts and the copies of it that
/// other apps recorded.
nonisolated struct WorkoutSessionGroup: Hashable, Sendable, Identifiable {
    let kept: WorkoutRecord
    let duplicates: [WorkoutRecord]

    var id: UUID { kept.id }

    /// Names of the other apps that recorded the same session.
    var otherSources: [String] {
        var seen: Set<String> = [kept.source]
        return duplicates.map(\.source).filter { seen.insert($0).inserted }
    }
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

    /// One session per group: the workout that counts, plus the copies other
    /// apps recorded of the same session. Oldest first.
    static func sessions(_ records: [WorkoutRecord]) -> [WorkoutSessionGroup] {
        var clusters: [[WorkoutRecord]] = []
        for record in records.sorted(by: { $0.start < $1.start }) {
            if let index = clusters.firstIndex(where: { cluster in cluster.contains { overlaps($0, record) } }) {
                clusters[index].append(record)
            } else {
                clusters.append([record])
            }
        }
        return clusters.map { cluster in
            let best = cluster.max { lhs, rhs in
                lhs.kcal == rhs.kcal ? lhs.duration < rhs.duration : lhs.kcal < rhs.kcal
            }!
            return WorkoutSessionGroup(kept: best, duplicates: cluster.filter { $0.id != best.id })
        }
        .sorted { $0.kept.start < $1.kept.start }
    }

    static func deduplicate(_ records: [WorkoutRecord]) -> (kept: [WorkoutRecord], duplicates: [WorkoutRecord]) {
        let groups = sessions(records)
        return (groups.map(\.kept), groups.flatMap(\.duplicates))
    }

    static func totalCalories(_ records: [WorkoutRecord]) -> Double {
        deduplicate(records).kept.map(\.kcal).reduce(0, +)
    }
}
