import Foundation
import Observation

/// User preferences. They are stored in this device's App Group defaults and
/// mirrored to the user's own iCloud key-value store, so the same settings
/// follow them to their other devices. Nothing goes to any third party.
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
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var isApplyingCloudValues = false

    private enum Key {
        static let unit = "unit"
        static let dailyGoal = "dailyGoal"
        static let quickAmounts = "quickAmounts"
        static let remindersEnabled = "remindersEnabled"
        static let reminderInterval = "reminderIntervalMinutes"
        static let reminderStart = "reminderStartMinutes"
        static let reminderEnd = "reminderEndMinutes"
    }

    init(defaults: UserDefaults = AppGroup.defaults, cloud: NSUbiquitousKeyValueStore? = .default) {
        self.defaults = defaults
        self.cloud = cloud
        let unit = defaults.string(forKey: Key.unit).flatMap(VolumeUnit.init(rawValue:)) ?? .milliliters
        self.unit = unit
        self.dailyGoal = defaults.object(forKey: Key.dailyGoal) as? Double ?? unit.defaultGoal
        let amounts = defaults.array(forKey: Key.quickAmounts) as? [Double] ?? []
        self.quickAmounts = amounts.count == 3 ? amounts : unit.defaultQuickAmounts
        self.remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true
        self.reminderIntervalMinutes = defaults.object(forKey: Key.reminderInterval) as? Int ?? 120
        self.reminderStartMinutes = defaults.object(forKey: Key.reminderStart) as? Int ?? 8 * 60
        self.reminderEndMinutes = defaults.object(forKey: Key.reminderEnd) as? Int ?? 22 * 60

        if let cloud {
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applyCloudValues() }
            }
            cloud.synchronize()
            applyCloudValues()
        }
    }

    /// Adopts whatever another device saved to iCloud. iCloud wins over the
    /// local copy, so the most recent change on any device ends up everywhere.
    private func applyCloudValues() {
        guard let cloud else { return }
        isApplyingCloudValues = true
        defer { isApplyingCloudValues = false }

        if let raw = cloud.string(forKey: Key.unit), let value = VolumeUnit(rawValue: raw), value != unit {
            unit = value
        }
        if let value = cloud.object(forKey: Key.dailyGoal) as? Double, value > 0, value != dailyGoal {
            dailyGoal = value
        }
        if let value = cloud.array(forKey: Key.quickAmounts) as? [Double], value.count == 3, value != quickAmounts {
            quickAmounts = value
        }
        if let value = cloud.object(forKey: Key.remindersEnabled) as? Bool, value != remindersEnabled {
            remindersEnabled = value
        }
        if let value = (cloud.object(forKey: Key.reminderInterval) as? NSNumber)?.intValue, value > 0, value != reminderIntervalMinutes {
            reminderIntervalMinutes = value
        }
        if let value = (cloud.object(forKey: Key.reminderStart) as? NSNumber)?.intValue, value != reminderStartMinutes {
            reminderStartMinutes = value
        }
        if let value = (cloud.object(forKey: Key.reminderEnd) as? NSNumber)?.intValue, value != reminderEndMinutes {
            reminderEndMinutes = value
        }
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

        if let cloud, !isApplyingCloudValues {
            cloud.set(unit.rawValue, forKey: Key.unit)
            cloud.set(dailyGoal, forKey: Key.dailyGoal)
            cloud.set(quickAmounts, forKey: Key.quickAmounts)
            cloud.set(remindersEnabled, forKey: Key.remindersEnabled)
            cloud.set(reminderIntervalMinutes, forKey: Key.reminderInterval)
            cloud.set(reminderStartMinutes, forKey: Key.reminderStart)
            cloud.set(reminderEndMinutes, forKey: Key.reminderEnd)
        }
        revision += 1
    }
}
