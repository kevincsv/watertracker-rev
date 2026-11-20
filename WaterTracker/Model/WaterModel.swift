import Foundation
import Observation
import WidgetKit

/// The app's state: today's entries, recent history, and the actions that
/// change them. Apple Health is the source of truth.
@MainActor
@Observable
final class WaterModel {
    static let shared = WaterModel()

    private(set) var entries: [WaterEntry] = []
    private(set) var todayTotal: Double = 0
    /// Daily totals for the last 30 days, oldest first, ending today.
    private(set) var history: [DayTotal] = []
    private(set) var access: HealthAccess = .notDetermined
    var errorMessage: String?

    @ObservationIgnored private let health: HealthStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var started = false

    init(health: HealthStore = .shared, settings: AppSettings = .shared) {
        self.health = health
        self.settings = settings
        self.todayTotal = DaySnapshot.load().total()
    }

    var progress: Double {
        settings.dailyGoal > 0 ? todayTotal / settings.dailyGoal : 0
    }

    var remaining: Double { max(settings.dailyGoal - todayTotal, 0) }

    var lastOwnEntry: WaterEntry? { entries.first(where: \.isOwn) }

    /// Called once when the app's UI appears: asks for permissions and starts
    /// listening for changes made in Apple Health.
    func start() async {
        guard !started else { return }
        started = true
        do {
            try await health.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
        await ReminderScheduler.requestAuthorization()
        health.observeChanges {
            Task { @MainActor in await WaterModel.shared.refresh() }
        }
        await refresh()
    }

    /// Reloads everything from Apple Health and updates widget and reminders.
    func refresh() async {
        access = health.access
        if await reload() {
            history = (try? await health.dailyTotals(days: 30)) ?? history
        }
        publish()
    }

    @discardableResult
    func log(_ milliliters: Double, at date: Date = .now) async -> Bool {
        guard milliliters > 0 else { return false }
        do {
            let entry = try await health.log(milliliters: milliliters, date: date)
            if await reload() {
                history = (try? await health.dailyTotals(days: 30)) ?? history
            } else {
                // Health data cannot be read while the device is locked, so
                // fall back to the last known total.
                entries.insert(entry, at: 0)
                todayTotal = DaySnapshot.load().total() + milliliters
            }
            access = health.access
            publish()
            return true
        } catch {
            access = health.access
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ entry: WaterEntry) async {
        guard entry.isOwn else { return }
        do {
            try await health.delete(entry)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoLast() async {
        guard let entry = lastOwnEntry else { return }
        await delete(entry)
    }

    /// Call after settings change so the widget and reminders follow.
    func settingsChanged() {
        publish()
    }

    private func reload() async -> Bool {
        do {
            let loaded = try await health.entries(on: .now)
            entries = loaded
            todayTotal = loaded.reduce(0) { $0 + $1.milliliters }
            return true
        } catch {
            return false
        }
    }

    private func publish() {
        DaySnapshot(
            day: Calendar.current.startOfDay(for: .now),
            totalMilliliters: todayTotal,
            goalMilliliters: settings.dailyGoal,
            unit: settings.unit
        ).save()
        WidgetCenter.shared.reloadAllTimelines()

        // Keeps the summary friends see up to date (does nothing unless
        // sharing with friends is turned on).
        if !history.isEmpty {
            var days = history
            if let last = days.last, Calendar.current.isDateInToday(last.date) {
                days[days.count - 1] = DayTotal(date: last.date, milliliters: todayTotal)
            }
            FriendsModel.shared.update(history: days, goal: settings.dailyGoal)
        }

        let total = todayTotal
        let lastDrink = entries.first?.date
        Task {
            await ReminderScheduler.reschedule(settings: settings, todayTotal: total, lastDrink: lastDrink)
        }
    }
}
