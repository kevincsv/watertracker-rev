import Foundation
import Testing
@testable import WaterTracker

struct ReminderPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    private func planner(interval: Int = 120, limit: Int = 48) -> ReminderPlanner {
        ReminderPlanner(intervalMinutes: interval, startMinutes: 8 * 60, endMinutes: 22 * 60, calendar: calendar, limit: limit)
    }

    @Test func countsFromLastDrink() {
        let dates = planner().fireDates(now: date(10, 10), lastDrink: date(10, 9, 30), goalReachedToday: false)
        #expect(dates.first == date(10, 11, 30))
        #expect(dates[1] == date(10, 13, 30))
    }

    @Test func overdueReminderFiresSoon() {
        let dates = planner().fireDates(now: date(10, 15), lastDrink: date(10, 9), goalReachedToday: false)
        #expect(dates.first == date(10, 15, 1))
    }

    @Test func staysInsideTheActiveHours() {
        let dates = planner().fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false)
        for fireDate in dates {
            let hour = calendar.component(.hour, from: fireDate)
            let minute = calendar.component(.minute, from: fireDate)
            #expect(hour >= 8)
            #expect(hour < 22 || (hour == 22 && minute == 0))
        }
    }

    @Test func rollsOverToNextMorning() {
        let dates = planner().fireDates(now: date(10, 21, 30), lastDrink: date(10, 21), goalReachedToday: false)
        #expect(dates.first == date(11, 8))
    }

    @Test func stopsForTheDayOnceGoalIsReached() {
        let dates = planner().fireDates(now: date(10, 12), lastDrink: date(10, 12), goalReachedToday: true)
        #expect(dates.first == date(11, 8))
    }

    @Test func respectsTheLimit() {
        let dates = planner(interval: 30, limit: 20).fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false)
        #expect(dates.count == 20)
        #expect(dates == dates.sorted())
    }

    @Test func endBeforeStartMeansUntilMidnight() {
        let planner = ReminderPlanner(intervalMinutes: 60, startMinutes: 20 * 60, endMinutes: 6 * 60, calendar: calendar, limit: 5)
        let dates = planner.fireDates(now: date(10, 12), lastDrink: nil, goalReachedToday: false)
        #expect(dates.first == date(10, 20))
    }

    // 10 January 2026 is a Saturday.
    @Test func skipsDaysThatAreOff() {
        var subject = planner()
        subject.weekdays = Set(2...6) // Monday to Friday
        let dates = subject.fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false)
        #expect(dates.first == date(12, 8))
        #expect(dates.allSatisfy { (2...6).contains(calendar.component(.weekday, from: $0)) })
    }

    @Test func capsRemindersPerDay() {
        var subject = planner(interval: 60)
        subject.dailyMax = 3
        let dates = subject.fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false)
        #expect(Array(dates.prefix(4)) == [date(10, 11), date(10, 12), date(10, 13), date(11, 8)])
    }

    @Test func dailyCapCountsRemindersAlreadyShown() {
        var subject = planner(interval: 60)
        subject.dailyMax = 3
        let dates = subject.fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false, sentToday: 3)
        #expect(dates.first == date(11, 8))
    }

    @Test func canKeepRemindingAfterTheGoal() {
        var subject = planner()
        subject.stopAtGoal = false
        let dates = subject.fireDates(now: date(10, 12), lastDrink: date(10, 12), goalReachedToday: true)
        #expect(dates.first == date(10, 14))
    }

    @Test func noDaysMeansNoReminders() {
        var subject = planner()
        subject.weekdays = []
        #expect(subject.fireDates(now: date(10, 10), lastDrink: nil, goalReachedToday: false).isEmpty)
    }
}

struct VolumeUnitTests {
    @Test func convertsOuncesBothWays() {
        let ml = VolumeUnit.fluidOunces.milliliters(from: 8)
        #expect(abs(ml - 236.588) < 0.01)
        #expect(abs(VolumeUnit.fluidOunces.value(fromMilliliters: ml) - 8) < 0.0001)
    }

    @Test func snapshotResetsOnANewDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let snapshot = DaySnapshot(day: today, totalMilliliters: 900, goalMilliliters: 2400, unit: .milliliters)
        #expect(snapshot.total(on: today.addingTimeInterval(3600)) == 900)
        #expect(snapshot.total(on: today.addingTimeInterval(86_400 * 2)) == 0)
    }

    @Test func streakIgnoresUnfinishedToday() {
        let days = [2400.0, 2500, 2400, 300].enumerated().map {
            DayTotal(date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), milliliters: $0.element)
        }
        let stats = HistoryStats(days: days, allDays: days, goal: 2400)
        #expect(stats.streak == 3)
        #expect(stats.daysMet == 3)
    }

    @Test func streakJudgesEachDayByItsOwnGoal() {
        let days = [2000.0, 2000, 2600].enumerated().map {
            DayTotal(date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), milliliters: $0.element)
        }
        // The goal was 2000 on the first two days and is 2500 today.
        let stats = HistoryStats(days: days, allDays: days) { $0 < days[2].date ? 2000 : 2500 }
        #expect(stats.streak == 3)
        #expect(HistoryStats(days: days, allDays: days, goal: 2500).streak == 1)
    }

    @Test func goalHistoryRemembersEachDay() throws {
        let defaults = try #require(UserDefaults(suiteName: "goal-history-test"))
        defaults.removePersistentDomain(forName: "goal-history-test")
        let calendar = Calendar.current
        let today = Date.now
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        GoalHistory.record(2000, on: yesterday, calendar: calendar, defaults: defaults)
        GoalHistory.record(2500, on: today, calendar: calendar, defaults: defaults)
        let goals = GoalHistory.load(defaults: defaults)
        #expect(GoalHistory.goal(on: yesterday, in: goals, fallback: 1) == 2000)
        #expect(GoalHistory.goal(on: today, in: goals, fallback: 1) == 2500)
        let older = try #require(calendar.date(byAdding: .day, value: -5, to: today))
        #expect(GoalHistory.goal(on: older, in: goals, fallback: 1) == 1)
        defaults.removePersistentDomain(forName: "goal-history-test")
    }
}
