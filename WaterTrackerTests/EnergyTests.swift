import Foundation
import Testing
@testable import WaterTracker

struct EnergyCalculatorTests {
    private let man = EnergyProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .light, goal: .maintain)

    @Test func mifflinStJeor() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        #expect(EnergyCalculator.bmr(sex: .male, age: 30, heightCm: 180, weightKg: 80) == 1780)
        // 10*60 + 6.25*165 - 5*28 - 161 = 1330.25
        #expect(EnergyCalculator.bmr(sex: .female, age: 28, heightCm: 165, weightKg: 60) == 1330.25)
    }

    @Test func incompleteProfileHasNoTarget() {
        var profile = man
        profile.heightCm = nil
        #expect(EnergyCalculator.target(profile: profile, exerciseToday: 0, adaptive: nil) == nil)
    }

    @Test func workoutsAndGoal() throws {
        let rest = try #require(EnergyCalculator.target(profile: man, exerciseToday: 0, adaptive: nil))
        #expect(rest.baseline == (1780 * 1.3).rounded())
        #expect(rest.calories == (1780 * 1.3).rounded())

        let trained = try #require(EnergyCalculator.target(profile: man, exerciseToday: 450, adaptive: nil))
        #expect(trained.calories == rest.calories + 450)

        var cutting = man
        cutting.goal = .lose
        cutting.weeklyRateKg = 0.5
        let cut = try #require(EnergyCalculator.target(profile: cutting, exerciseToday: 0, adaptive: nil))
        #expect(cut.goalAdjustment == -550)
        #expect(cut.calories == rest.calories - 550)
        #expect(cut.proteinGrams == 176)
    }

    @Test func safetyFloor() throws {
        var small = EnergyProfile(sex: .female, age: 60, heightCm: 150, weightKg: 45, activity: .sedentary, goal: .lose)
        small.weeklyRateKg = 1
        let target = try #require(EnergyCalculator.target(profile: small, exerciseToday: 0, adaptive: nil))
        #expect(target.floorApplied)
        #expect(target.calories == 1200)
    }

    @Test func adaptiveBlendIsClamped() throws {
        let formula = 1780 * 1.3
        let wild = AdaptiveEstimate(tdee: 5000, baseline: 5000, confidence: 1, loggedDays: 28)
        let target = try #require(EnergyCalculator.target(profile: man, exerciseToday: 0, adaptive: wild))
        #expect(target.baseline == (formula * 1.35).rounded())

        let half = AdaptiveEstimate(tdee: 2500, baseline: 2500, confidence: 0.5, loggedDays: 12)
        let blended = try #require(EnergyCalculator.target(profile: man, exerciseToday: 0, adaptive: half))
        #expect(blended.baseline == ((formula + 2500) / 2).rounded())
    }

    @Test func macrosAddUp() throws {
        let target = try #require(EnergyCalculator.target(profile: man, exerciseToday: 300, adaptive: nil))
        let fromMacros = target.proteinGrams * 4 + target.carbGrams * 4 + target.fatGrams * 9
        #expect(abs(fromMacros - target.calories) < 10)
    }
}

struct WorkoutDeduplicatorTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func workout(_ startMinute: Double, _ minutes: Double, kcal: Double, source: String) -> WorkoutRecord {
        let start = base.addingTimeInterval(startMinute * 60)
        return WorkoutRecord(id: UUID(), start: start, end: start.addingTimeInterval(minutes * 60), kcal: kcal, activity: "Fuerza", source: source)
    }

    @Test func sameSessionFromTwoAppsCountsOnce() {
        let whoop = workout(0, 60, kcal: 420, source: "WHOOP")
        let watch = workout(3, 55, kcal: 380, source: "Apple Watch")
        let result = WorkoutDeduplicator.deduplicate([watch, whoop])
        #expect(result.kept == [whoop])
        #expect(result.duplicates == [watch])
        #expect(WorkoutDeduplicator.totalCalories([watch, whoop]) == 420)
    }

    @Test func separateSessionsBothCount() {
        let morning = workout(0, 45, kcal: 300, source: "WHOOP")
        let evening = workout(600, 30, kcal: 250, source: "WHOOP")
        let barelyTouching = workout(40, 60, kcal: 200, source: "Apple Watch")
        let result = WorkoutDeduplicator.deduplicate([evening, morning, barelyTouching])
        #expect(result.kept.count == 3)
        #expect(WorkoutDeduplicator.totalCalories([morning, evening, barelyTouching]) == 750)
    }

    @Test func lateUploadReplacesNothingTwice() {
        let watch = workout(0, 50, kcal: 350, source: "Apple Watch")
        let whoopLater = workout(1, 50, kcal: 360, source: "WHOOP")
        let whoopWalk = workout(2, 20, kcal: 90, source: "WHOOP")
        let result = WorkoutDeduplicator.deduplicate([watch, whoopLater, whoopWalk])
        #expect(result.kept.map(\.kcal) == [360])
        #expect(result.duplicates.count == 2)
    }
}

struct WeightTrendTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let day0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }

    @Test func trendSmoothsNoise() {
        let points = (0..<20).map { WeightPoint(date: day($0), kilograms: $0.isMultiple(of: 2) ? 81 : 79) }
        let trend = WeightTrend.trend(points, calendar: calendar)
        #expect(trend.count == 20)
        #expect(trend.allSatisfy { (79.5...81).contains($0.kilograms) })
    }

    @Test func dailyAveragesSameDay() {
        let points = [
            WeightPoint(date: day(0), kilograms: 80),
            WeightPoint(date: day(0).addingTimeInterval(3600), kilograms: 81),
        ]
        #expect(WeightTrend.daily(points, calendar: calendar).map(\.kilograms) == [80.5])
    }

    @Test func slopeOfSteadyLoss() throws {
        let points = (0..<28).map { WeightPoint(date: day($0), kilograms: 80 - Double($0) * 0.05) }
        let slope = try #require(WeightTrend.slopePerDay(points, lastDays: 28, now: day(28)))
        #expect(abs(slope + 0.05) < 0.0001)
        #expect(WeightTrend.slopePerDay(Array(points.prefix(3)), lastDays: 28, now: day(28)) == nil)
    }
}

struct AdaptiveExpenditureTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func energyBalance() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let today = calendar.startOfDay(for: now)
        let days = (1...28).map { n in
            DayEnergy(date: calendar.date(byAdding: .day, value: -n, to: today)!, intake: 2200, exercise: 300)
        }
        // Losing 0.5 kg a week for four weeks, weighed every day.
        let weights = (0...28).map { n in
            WeightPoint(date: calendar.date(byAdding: .day, value: -28 + n, to: today)!, kilograms: 80 - Double(n) * 0.5 / 7)
        }
        let estimate = try #require(AdaptiveExpenditure.estimate(days: days, weights: weights, now: now, calendar: calendar))
        // 2200 + 0.5/7 * 7700 = 2750 total, 2450 without workouts.
        #expect(abs(estimate.tdee - 2750) < 2)
        #expect(abs(estimate.baseline - (estimate.tdee - 300)) < 1)
        #expect(estimate.confidence == 1)
    }

    @Test func needsEnoughLoggedDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let days = (1...5).map { DayEnergy(date: now.addingTimeInterval(-Double($0) * 86_400), intake: 2000, exercise: 0) }
        #expect(AdaptiveExpenditure.estimate(days: days, weights: [], now: now) == nil)
    }
}
