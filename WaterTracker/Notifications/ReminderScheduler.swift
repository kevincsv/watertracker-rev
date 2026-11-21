import Foundation
import UserNotifications

nonisolated enum ReminderID {
    static let category = "WATER_REMINDER"
    static let logAction = "LOG_WATER"
    static let amountKey = "milliliters"
    static let prefix = "water-reminder-"
}

/// Schedules local notifications. Nothing here talks to a server: the
/// notifications are created and delivered entirely on this device.
@MainActor
enum ReminderScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    /// Asks for permission the first time; afterwards reports the current state.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// The reschedule in progress. Each new one waits for it, so two that
    /// start close together cannot interleave and leave a mix of both.
    private static var inFlight: Task<Void, Never>?

    static func reschedule(settings: AppSettings, todayTotal: Double, lastDrink: Date?, now: Date = .now) async {
        let previous = inFlight
        let task = Task {
            await previous?.value
            await replaceReminders(settings: settings, todayTotal: todayTotal, lastDrink: lastDrink, now: now)
        }
        inFlight = task
        await task.value
    }

    private static func replaceReminders(settings: AppSettings, todayTotal: Double, lastDrink: Date?, now: Date) async {
        let calendar = Calendar.current
        let sentToday = await countRemindersShownToday(now: now, calendar: calendar)
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        guard settings.remindersEnabled, await isAuthorized() else { return }

        let unit = settings.unit
        let quickAmount = settings.quickAmounts.first ?? unit.defaultQuickAmounts[0]
        registerCategory(quickAmountLabel: unit.format(quickAmount))

        let planner = ReminderPlanner(
            intervalMinutes: settings.reminderIntervalMinutes,
            startMinutes: settings.reminderStartMinutes,
            endMinutes: settings.reminderEndMinutes,
            weekdays: settings.reminderWeekdays,
            dailyMax: settings.reminderDailyMax,
            stopAtGoal: settings.remindersStopAtGoal
        )
        let remaining = max(settings.dailyGoal - todayTotal, 0)
        let dates = planner.fireDates(now: now, lastDrink: lastDrink, goalReachedToday: remaining <= 0, sentToday: sentToday)

        var greetedDays: Set<Date> = []
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to drink water")
            if !calendar.isDate(date, inSameDayAs: now) {
                // Only the first reminder of a later day is a "good morning";
                // the app cannot know that day's total in advance.
                let isFirstOfDay = greetedDays.insert(calendar.startOfDay(for: date)).inserted
                content.body = isFirstOfDay
                    ? String(localized: "Start the day with a glass of water.")
                    : String(localized: "A glass of water keeps you on track.")
            } else if remaining > 0 {
                content.body = String(localized: "\(unit.format(remaining)) left to reach today's goal.")
            } else {
                content.body = String(localized: "Goal reached. One more glass keeps you going.")
            }
            content.sound = settings.reminderSound.notificationSound
            content.categoryIdentifier = ReminderID.category
            content.userInfo = [ReminderID.amountKey: quickAmount]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(ReminderID.prefix)\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// How many reminders have already been shown today, so the daily
    /// maximum holds even though every reschedule clears the shown ones.
    /// Kept in this device's own defaults; it is not synced.
    private static func countRemindersShownToday(now: Date, calendar: Calendar) async -> Int {
        let defaults = UserDefaults.standard
        let today = calendar.startOfDay(for: now)
        let storedDay = defaults.object(forKey: ShownCount.dayKey) as? Date
        let sameDay = storedDay.map { calendar.isDate($0, inSameDayAs: today) } == true
        // Each shown reminder is remembered by the moment it was delivered,
        // not just counted: clearing shown notifications takes the system a
        // moment, so the same one can still be listed on the next pass and
        // must not count twice.
        var shown = Set(sameDay ? (defaults.array(forKey: ShownCount.timesKey) as? [Double] ?? []) : [])
        // Reminders counted by an earlier version, which kept only a number.
        let legacy = sameDay ? defaults.integer(forKey: ShownCount.countKey) : 0
        for notification in await center.deliveredNotifications()
        where notification.request.identifier.hasPrefix(ReminderID.prefix) && calendar.isDate(notification.date, inSameDayAs: now) {
            shown.insert(notification.date.timeIntervalSince1970.rounded())
        }
        defaults.set(today, forKey: ShownCount.dayKey)
        defaults.set(shown.sorted(), forKey: ShownCount.timesKey)
        defaults.set(legacy, forKey: ShownCount.countKey)
        return shown.count + legacy
    }

    private enum ShownCount {
        static let dayKey = "remindersShownDay"
        static let countKey = "remindersShownCount"
        static let timesKey = "remindersShownTimes"
    }

    private static func registerCategory(quickAmountLabel: String) {
        let action = UNNotificationAction(
            identifier: ReminderID.logAction,
            title: String(localized: "Log \(quickAmountLabel)"),
            options: []
        )
        let category = UNNotificationCategory(identifier: ReminderID.category, actions: [action], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
}

/// Handles taps on the "Log" button of a reminder, and shows reminders as
/// banners while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderID.logAction,
              let amount = response.notification.request.content.userInfo[ReminderID.amountKey] as? Double
        else { return }
        await WaterModel.shared.log(amount)
    }
}
