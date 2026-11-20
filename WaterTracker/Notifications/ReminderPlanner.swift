import Foundation

/// Works out when reminders should fire. Pure logic with no system calls, so
/// it can be unit tested.
nonisolated struct ReminderPlanner: Sendable {
    var intervalMinutes: Int
    /// Minutes after midnight when reminders may start.
    var startMinutes: Int
    /// Minutes after midnight when reminders stop.
    var endMinutes: Int
    /// Days of the week when reminders may fire, as `Calendar` weekday
    /// numbers (1 is Sunday, 7 is Saturday).
    var weekdays: Set<Int> = Set(1...7)
    /// The most reminders on any one day. 0 means no limit.
    var dailyMax = 0
    /// Whether reminders stop for the rest of the day once the goal is met.
    var stopAtGoal = true
    var calendar: Calendar = .current
    /// iOS keeps at most 64 pending local notifications per app.
    var limit = 48

    /// - Parameter sentToday: reminders already shown today, so the daily
    ///   maximum also covers the ones that have fired before now.
    func fireDates(now: Date, lastDrink: Date?, goalReachedToday: Bool, sentToday: Int = 0) -> [Date] {
        let activeDays = weekdays.intersection(1...7)
        guard !activeDays.isEmpty else { return [] }

        let interval = TimeInterval(max(intervalMinutes, 5) * 60)
        let today = calendar.startOfDay(for: now)

        var candidate: Date
        if goalReachedToday && stopAtGoal {
            candidate = windowStart(on: dayAfter(today))
        } else {
            let drinkToday = lastDrink.flatMap { calendar.isDate($0, inSameDayAs: now) && $0 <= now ? $0 : nil }
            candidate = max((drinkToday ?? now).addingTimeInterval(interval), now.addingTimeInterval(60))
        }

        var dates: [Date] = []
        var countedDay = today
        var countToday = max(sentToday, 0)
        // A safety stop, so a very sparse schedule cannot loop for ever.
        let lastDay = calendar.date(byAdding: .day, value: 60, to: today) ?? today.addingTimeInterval(60 * 86_400)

        while dates.count < limit && candidate < lastDay {
            let day = calendar.startOfDay(for: candidate)
            if day != countedDay {
                countedDay = day
                countToday = 0
            }
            let dayIsFull = dailyMax > 0 && countToday >= dailyMax
            if candidate > windowEnd(on: day) || dayIsFull || !activeDays.contains(calendar.component(.weekday, from: day)) {
                candidate = windowStart(on: dayAfter(day))
                continue
            }
            candidate = max(candidate, windowStart(on: day))
            dates.append(candidate)
            countToday += 1
            candidate = candidate.addingTimeInterval(interval)
        }
        return dates
    }

    private var clampedStart: Int { min(max(startMinutes, 0), 23 * 60 + 59) }

    /// An end at or before the start means "until the end of the day".
    private var clampedEnd: Int {
        endMinutes > clampedStart ? min(endMinutes, 23 * 60 + 59) : 23 * 60 + 59
    }

    private func windowStart(on day: Date) -> Date { time(clampedStart, on: day) }
    private func windowEnd(on day: Date) -> Date { time(clampedEnd, on: day) }

    private func time(_ minutes: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func dayAfter(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }
}
