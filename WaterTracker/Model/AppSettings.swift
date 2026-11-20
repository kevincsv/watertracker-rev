import Foundation
import Observation

/// User preferences. They are stored in this app's own defaults and
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
    /// Days of the week with reminders, as `Calendar` weekday numbers
    /// (1 is Sunday, 7 is Saturday).
    var reminderWeekdays: Set<Int> { didSet { save() } }
    /// The most reminders on any one day. 0 means no limit.
    var reminderDailyMax: Int { didSet { save() } }
    /// Whether reminders stop for the rest of the day once the goal is met.
    var remindersStopAtGoal: Bool { didSet { save() } }
    var reminderSound: ReminderSound { didSet { save() } }

    // Automatic goal. When on, `dailyGoal` is recalculated from these and
    // from Apple Health, so the rest of the app needs no changes.
    var autoGoal: Bool { didSet { save() } }
    var sexChoice: SexChoice { didSet { save() } }
    /// Weight typed by the user, in kilograms. 0 means "use Apple Health".
    var manualWeightKilograms: Double { didSet { save() } }
    var hotWeather: Bool { didSet { save() } }
    var statusChoice: StatusChoice { didSet { save() } }
    var cycleAdjustment: Bool { didSet { save() } }

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
        static let autoGoal = "autoGoal"
        static let sexChoice = "goalSex"
        static let manualWeight = "goalWeightKg"
        static let hotWeather = "goalHotWeather"
        static let statusChoice = "goalStatus"
        static let cycleAdjustment = "goalCycle"
        static let reminderWeekdays = "reminderWeekdays"
        static let reminderDailyMax = "reminderDailyMax"
        static let remindersStopAtGoal = "remindersStopAtGoal"
        static let reminderSound = "reminderSound"
    }

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default) {
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
        self.autoGoal = defaults.bool(forKey: Key.autoGoal)
        self.sexChoice = defaults.string(forKey: Key.sexChoice).flatMap(SexChoice.init(rawValue:)) ?? .health
        self.manualWeightKilograms = defaults.double(forKey: Key.manualWeight)
        self.hotWeather = defaults.bool(forKey: Key.hotWeather)
        self.statusChoice = defaults.string(forKey: Key.statusChoice).flatMap(StatusChoice.init(rawValue:)) ?? .health
        self.cycleAdjustment = defaults.bool(forKey: Key.cycleAdjustment)
        self.reminderWeekdays = (defaults.array(forKey: Key.reminderWeekdays) as? [Int]).map(Set.init) ?? Set(1...7)
        self.reminderDailyMax = defaults.object(forKey: Key.reminderDailyMax) as? Int ?? 0
        self.remindersStopAtGoal = defaults.object(forKey: Key.remindersStopAtGoal) as? Bool ?? true
        self.reminderSound = defaults.string(forKey: Key.reminderSound).flatMap(ReminderSound.init(rawValue:)) ?? .system

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
        if let value = cloud.object(forKey: Key.autoGoal) as? Bool, value != autoGoal {
            autoGoal = value
        }
        if let raw = cloud.string(forKey: Key.sexChoice), let value = SexChoice(rawValue: raw), value != sexChoice {
            sexChoice = value
        }
        if let value = cloud.object(forKey: Key.manualWeight) as? Double, value >= 0, value != manualWeightKilograms {
            manualWeightKilograms = value
        }
        if let value = cloud.object(forKey: Key.hotWeather) as? Bool, value != hotWeather {
            hotWeather = value
        }
        if let raw = cloud.string(forKey: Key.statusChoice), let value = StatusChoice(rawValue: raw), value != statusChoice {
            statusChoice = value
        }
        if let value = cloud.object(forKey: Key.cycleAdjustment) as? Bool, value != cycleAdjustment {
            cycleAdjustment = value
        }
        if let value = (cloud.array(forKey: Key.reminderWeekdays) as? [NSNumber]).map({ Set($0.map(\.intValue)) }), value != reminderWeekdays {
            reminderWeekdays = value
        }
        if let value = (cloud.object(forKey: Key.reminderDailyMax) as? NSNumber)?.intValue, value >= 0, value != reminderDailyMax {
            reminderDailyMax = value
        }
        if let value = cloud.object(forKey: Key.remindersStopAtGoal) as? Bool, value != remindersStopAtGoal {
            remindersStopAtGoal = value
        }
        if let raw = cloud.string(forKey: Key.reminderSound), let value = ReminderSound(rawValue: raw), value != reminderSound {
            reminderSound = value
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
        defaults.set(autoGoal, forKey: Key.autoGoal)
        defaults.set(sexChoice.rawValue, forKey: Key.sexChoice)
        defaults.set(manualWeightKilograms, forKey: Key.manualWeight)
        defaults.set(hotWeather, forKey: Key.hotWeather)
        defaults.set(statusChoice.rawValue, forKey: Key.statusChoice)
        defaults.set(cycleAdjustment, forKey: Key.cycleAdjustment)
        defaults.set(reminderWeekdays.sorted(), forKey: Key.reminderWeekdays)
        defaults.set(reminderDailyMax, forKey: Key.reminderDailyMax)
        defaults.set(remindersStopAtGoal, forKey: Key.remindersStopAtGoal)
        defaults.set(reminderSound.rawValue, forKey: Key.reminderSound)

        if let cloud, !isApplyingCloudValues {
            cloud.set(unit.rawValue, forKey: Key.unit)
            cloud.set(dailyGoal, forKey: Key.dailyGoal)
            cloud.set(quickAmounts, forKey: Key.quickAmounts)
            cloud.set(remindersEnabled, forKey: Key.remindersEnabled)
            cloud.set(reminderIntervalMinutes, forKey: Key.reminderInterval)
            cloud.set(reminderStartMinutes, forKey: Key.reminderStart)
            cloud.set(reminderEndMinutes, forKey: Key.reminderEnd)
            cloud.set(autoGoal, forKey: Key.autoGoal)
            cloud.set(sexChoice.rawValue, forKey: Key.sexChoice)
            cloud.set(manualWeightKilograms, forKey: Key.manualWeight)
            cloud.set(hotWeather, forKey: Key.hotWeather)
            cloud.set(statusChoice.rawValue, forKey: Key.statusChoice)
            cloud.set(cycleAdjustment, forKey: Key.cycleAdjustment)
            cloud.set(reminderWeekdays.sorted(), forKey: Key.reminderWeekdays)
            cloud.set(reminderDailyMax, forKey: Key.reminderDailyMax)
            cloud.set(remindersStopAtGoal, forKey: Key.remindersStopAtGoal)
            cloud.set(reminderSound.rawValue, forKey: Key.reminderSound)
        }
        revision += 1
    }
}

/// Where the automatic goal takes sex from.
nonisolated enum SexChoice: String, Sendable, CaseIterable {
    case health
    case female
    case male
}

/// Where the automatic goal takes pregnancy or breastfeeding from.
nonisolated enum StatusChoice: String, Sendable, CaseIterable {
    case health
    case none
    case pregnant
    case lactating
}
