import Foundation
import Observation

/// User preferences, stored only in this device's App Group defaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var unit: VolumeUnit { didSet { save() } }
    var dailyGoal: Double { didSet { save() } }
    var quickAmounts: [Double] { didSet { save() } }
    var remindersEnabled: Bool { didSet { save() } }
    var reminderIntervalMinutes: Int { didSet { save() } }
    /// Minutes after midnight when reminders may start.
    var reminderStartMinutes: Int { didSet { save() } }
    /// Minutes after midnight when reminders stop.
    var reminderEndMinutes: Int { didSet { save() } }

    /// Bumped on every change so views can react to "anything changed".
    private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let unit = "unit"
        static let dailyGoal = "dailyGoal"
        static let quickAmounts = "quickAmounts"
        static let remindersEnabled = "remindersEnabled"
        static let reminderInterval = "reminderIntervalMinutes"
        static let reminderStart = "reminderStartMinutes"
        static let reminderEnd = "reminderEndMinutes"
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let unit = defaults.string(forKey: Key.unit).flatMap(VolumeUnit.init(rawValue:)) ?? .milliliters
        self.unit = unit
        self.dailyGoal = defaults.object(forKey: Key.dailyGoal) as? Double ?? unit.defaultGoal
        let amounts = defaults.array(forKey: Key.quickAmounts) as? [Double] ?? []
        self.quickAmounts = amounts.count == 3 ? amounts : unit.defaultQuickAmounts
        self.remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true
        self.reminderIntervalMinutes = defaults.object(forKey: Key.reminderInterval) as? Int ?? 120
        self.reminderStartMinutes = defaults.object(forKey: Key.reminderStart) as? Int ?? 8 * 60
        self.reminderEndMinutes = defaults.object(forKey: Key.reminderEnd) as? Int ?? 22 * 60
    }

    /// Switches the display unit and resets goal and quick amounts to round
    /// numbers in that unit.
    func changeUnit(to newUnit: VolumeUnit) {
        guard newUnit != unit else { return }
        unit = newUnit
        dailyGoal = newUnit.defaultGoal
        quickAmounts = newUnit.defaultQuickAmounts
    }

    private func save() {
        defaults.set(unit.rawValue, forKey: Key.unit)
        defaults.set(dailyGoal, forKey: Key.dailyGoal)
        defaults.set(quickAmounts, forKey: Key.quickAmounts)
        defaults.set(remindersEnabled, forKey: Key.remindersEnabled)
        defaults.set(reminderIntervalMinutes, forKey: Key.reminderInterval)
        defaults.set(reminderStartMinutes, forKey: Key.reminderStart)
        defaults.set(reminderEndMinutes, forKey: Key.reminderEnd)
        revision += 1
    }
}
