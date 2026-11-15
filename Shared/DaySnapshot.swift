import Foundation

/// Storage shared between the app and its widget. It lives in the App Group
/// container on this device and is never synced anywhere.
nonisolated enum AppGroup {
    static let identifier = "group.com.kevincsv.hidrata"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// The last known total for a day, written by the app so the widget can show
/// progress without reading Apple Health itself.
nonisolated struct DaySnapshot: Codable, Sendable, Equatable {
    var day: Date
    var totalMilliliters: Double
    var goalMilliliters: Double
    var unit: VolumeUnit

    private static let key = "daySnapshot"

    static let empty = DaySnapshot(day: .distantPast, totalMilliliters: 0, goalMilliliters: 2400, unit: .milliliters)

    /// The total for `date`, or zero when the snapshot belongs to another day.
    func total(on date: Date = .now, calendar: Calendar = .current) -> Double {
        calendar.isDate(day, inSameDayAs: date) ? totalMilliliters : 0
    }

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> DaySnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DaySnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
