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

    static func reschedule(settings: AppSettings, todayTotal: Double, lastDrink: Date?, now: Date = .now) async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        guard settings.remindersEnabled, await isAuthorized() else { return }

        let unit = settings.unit
        let quickAmount = settings.quickAmounts.first ?? unit.defaultQuickAmounts[0]
        registerCategory(quickAmountLabel: unit.format(quickAmount))

        let planner = ReminderPlanner(
            intervalMinutes: settings.reminderIntervalMinutes,
            startMinutes: settings.reminderStartMinutes,
            endMinutes: settings.reminderEndMinutes
        )
        let remaining = max(settings.dailyGoal - todayTotal, 0)
        let dates = planner.fireDates(now: now, lastDrink: lastDrink, goalReachedToday: remaining <= 0)
        let calendar = Calendar.current

        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to drink water")
            content.body = calendar.isDate(date, inSameDayAs: now)
                ? String(localized: "\(unit.format(remaining)) left to reach today's goal.")
                : String(localized: "Start the day with a glass of water.")
            content.sound = .default
            content.categoryIdentifier = ReminderID.category
            content.userInfo = [ReminderID.amountKey: quickAmount]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(ReminderID.prefix)\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
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
