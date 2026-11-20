import Foundation
import Testing
@testable import WaterTracker

struct WeeklyComparisonTests {
    /// Weeks start on Monday, in UTC.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// 2026-01-05 is a Monday.
    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
    }

    private func summary(_ name: String, goal: Double, _ amounts: [Int: Double]) -> WaterSummary {
        let history = amounts.map { DayTotal(date: day($0.key), milliliters: $0.value) }.sorted { $0.date < $1.date }
        return WaterSummary(name: name, goalMilliliters: goal, history: history, updatedAt: day(1), calendar: calendar)
    }

    @Test func summaryKeepsDailyTotalsByDay() {
        let summary = summary("Ana", goal: 2000, [5: 1500, 6: 2100])
        #expect(summary.milliliters(on: day(5), calendar: calendar) == 1500)
        #expect(summary.milliliters(on: day(6), calendar: calendar) == 2100)
        #expect(summary.milliliters(on: day(7), calendar: calendar) == 0)
    }

    @Test func summaryRoundTripsThroughJSON() throws {
        let original = summary("Ana", goal: 2000, [5: 1500])
        let decoded = try JSONDecoder().decode(WaterSummary.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func currentWeekOnlyCountsDaysSoFar() {
        let me = Participant.me(summary("Me", goal: 2000, [5: 2000, 6: 1000, 7: 3000]))
        let comparison = WeeklyComparison(participants: [me], now: day(7).addingTimeInterval(3600), calendar: calendar)
        #expect(comparison.weekStart == day(5))
        #expect(comparison.days.count == 3)
        let standing = comparison.standings[0]
        #expect(standing.total == 6000)
        #expect(standing.dailyAverage == 2000)
        #expect(standing.daysGoalMet == 2)
        #expect(standing.goalRatio == 1)
    }

    @Test func lastWeekHasSevenDays() {
        let me = Participant.me(summary("Me", goal: 2000, [1: 1000, 4: 500, 5: 9999]))
        let comparison = WeeklyComparison(participants: [me], weeksAgo: 1, now: day(7), calendar: calendar)
        #expect(comparison.weekStart == calendar.date(byAdding: .day, value: -7, to: day(5)))
        #expect(comparison.days.count == 7)
        #expect(comparison.standings[0].total == 1500)
    }

    @Test func ranksByOwnGoalNotRawAmount() {
        // Ana drinks less than Ben but gets closer to her own, smaller goal.
        let ana = Participant(id: "ana", isMe: false, summary: summary("Ana", goal: 1500, [5: 1500]))
        let ben = Participant(id: "ben", isMe: false, summary: summary("Ben", goal: 3000, [5: 2000]))
        let comparison = WeeklyComparison(participants: [ben, ana], now: day(5), calendar: calendar)
        #expect(comparison.standings.map(\.id) == ["ana", "ben"])
    }

    @Test func sameContentIgnoresUpdateTime() {
        var a = summary("Ana", goal: 2000, [5: 1500])
        let b = a
        a.updatedAt = day(9)
        #expect(a.hasSameContent(as: b))
        a.days[WaterSummary.key(for: day(6), calendar: calendar)] = 100
        #expect(!a.hasSameContent(as: b))
    }
}
