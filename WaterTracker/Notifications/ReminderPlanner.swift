import Foundation

/// Works out when reminders should fire. Pure logic with no system calls, so
/// it can be unit tested.
nonisolated struct ReminderPlanner: Sendable {
    var intervalMinutes: Int
    /// Minutes after midnight when reminders may start.
    var startMinutes: Int
    /// Minutes after midnight when reminders stop.
    var endMinutes: Int
    var calendar: Calendar = .current
    /// iOS keeps at most 64 pending local notifications per app.
    var limit = 48

    func fireDates(now: Date, lastDrink: Date?, goalReachedToday: Bool) -> [Date] {
        let interval = TimeInterval(max(intervalMinutes, 5) * 60)
        let today = calendar.startOfDay(for: now)

        var candidate: Date
        if goalReachedToday {
            candidate = windowStart(on: dayAfter(today))
        } else {
            let drinkToday = lastDrink.flatMap { calendar.isDate($0, inSameDayAs: now) && $0 <= now ? $0 : nil }
            candidate = max((drinkToday ?? now).addingTimeInterval(interval), now.addingTimeInterval(60))
        }

        var dates: [Date] = []
        while dates.count < limit {
            let day = calendar.startOfDay(for: candidate)
            if candidate > windowEnd(on: day) {
                candidate = windowStart(on: dayAfter(day))
                continue
            }
            candidate = max(candidate, windowStart(on: day))
            dates.append(candidate)
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
