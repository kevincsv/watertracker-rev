import Foundation
import Testing
@testable import WaterTracker

struct GoalCalculatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// `offset` days after January 1.
    private func dayOfYear(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day(1, 1))!
    }

    /// Bleeding on `length` days starting `offset` days after January 1.
    private func period(startingAt offset: Int, length: Int = 5) -> [Date] {
        (0..<length).map { dayOfYear(offset + $0) }
    }

    @Test func fallsBackToEFSAWithoutWeight() {
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female)).total == 2000)
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .male)).total == 2500)
    }

    @Test func usesWeightAndSex() {
        // 70 kg x 35 ml = 2450 ml.
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .male, weightKilograms: 70)).total == 2450)
        // 60 kg x 31 ml = 1860 ml, rounded to 1850.
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female, weightKilograms: 60)).total == 1850)
    }

    @Test func addsWorkoutsAndHeat() {
        let inputs = GoalInputs(sex: .male, weightKilograms: 70, workoutMinutes: 60, hotWeather: true)
        let breakdown = GoalCalculator.goal(for: inputs)
        #expect(breakdown.total == 2450 + 500 + 500)
        #expect(breakdown.items.map(\.reason) == [.body, .activity, .heat])
    }

    @Test func capsWorkoutsAndTotal() {
        let long = GoalCalculator.goal(for: GoalInputs(sex: .male, weightKilograms: 70, workoutMinutes: 600))
        #expect(long.total == 2450 + 1500)
        let huge = GoalCalculator.goal(for: GoalInputs(sex: .male, weightKilograms: 250, workoutMinutes: 600, hotWeather: true))
        #expect(huge.total == 6000)
    }

    @Test func pregnancyLactationAndCycleOnlyForWomen() {
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female, status: .pregnant)).total == 2300)
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female, status: .lactating)).total == 2700)
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female, cyclePhase: .menstruation)).total == 2250)
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .female, cyclePhase: .luteal)).total == 2200)
        #expect(GoalCalculator.goal(for: GoalInputs(sex: .male, status: .pregnant, cyclePhase: .luteal)).total == 2500)
    }

    @Test func overlappingWorkoutsCountOnce() {
        let start = day(1, 10, hour: 7)
        let strap = DateInterval(start: start, duration: 3600)
        let phone = DateInterval(start: start.addingTimeInterval(1800), duration: 3600)
        let evening = DateInterval(start: start.addingTimeInterval(10 * 3600), duration: 1800)
        #expect(GoalCalculator.workoutMinutes([evening, phone, strap]) == 90 + 30)
        #expect(GoalCalculator.workoutMinutes([]) == 0)
    }

    @Test func periodDaysAreMenstruation() {
        let days = period(startingAt: 0)
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day(1, 3), calendar: calendar) == .menstruation)
        // The day after the last logged day still counts.
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day(1, 6), calendar: calendar) == .menstruation)
    }

    @Test func estimatesLutealPhase() {
        let days = period(startingAt: 0)
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day(1, 10), calendar: calendar) == .other)
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day(1, 20), calendar: calendar) == .luteal)
    }

    @Test func usesOwnCycleLength() {
        // Two 35-day cycles: the luteal phase starts on day 21, not day 14.
        let days = period(startingAt: 0) + period(startingAt: 35) + period(startingAt: 70)
        let lastStart = dayOfYear(70)
        let day18 = calendar.date(byAdding: .day, value: 18, to: lastStart)!
        let day22 = calendar.date(byAdding: .day, value: 22, to: lastStart)!
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day18, calendar: calendar) == .other)
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day22, calendar: calendar) == .luteal)
    }

    @Test func noGuessWithoutRecentData() {
        #expect(GoalCalculator.cyclePhase(bleedingDays: [], today: day(1, 10), calendar: calendar) == nil)
        let days = period(startingAt: 0)
        #expect(GoalCalculator.cyclePhase(bleedingDays: days, today: day(3, 1), calendar: calendar) == nil)
    }
}
