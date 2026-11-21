import Foundation
import Observation

/// Today's meals and totals, loaded from the Health app.
@Observable
final class FoodModel {
    static let shared = FoodModel()

    private let health = NutritionStore.shared
    private var started = false

    private(set) var entries: [FoodEntry] = []
    /// Calories eaten today from every app that writes to Health.
    private(set) var eaten: Double = 0
    /// Active calories burned today, as written by WHOOP or a watch.
    private(set) var burned: Double = 0
    private(set) var access: HealthAccess = .notDetermined
    var errorMessage: String?

    // Inputs for the calorie target, read from Health.
    private(set) var weights: [WeightPoint] = []
    private(set) var healthBirth: DateComponents?
    private(set) var healthHeightCm: Double?
    private(set) var healthSex: BodySex?
    private(set) var healthStatus: ReproductiveStatus = .none
    /// Today's workouts that count, one per session.
    private(set) var workoutsToday: [WorkoutRecord] = []
    /// Workouts ignored today because another app recorded the same session.
    private(set) var duplicateWorkoutsToday: [WorkoutRecord] = []
    private(set) var adaptiveEstimate: AdaptiveEstimate?
    /// Workouts from the Health app over the last four weeks, one per
    /// session, newest first. Shown in the Workouts tab.
    private(set) var recentWorkouts: [WorkoutSessionGroup] = []

    private let profileSettings = FoodProfileSettings.shared
    private let appSettings = AppSettings.shared

    var exerciseToday: Double {
        workoutsToday.map(\.kcal).reduce(0, +)
    }

    var weightTrend: [WeightPoint] {
        WeightTrend.trend(weights)
    }

    /// Kilograms per week over the last four weeks.
    var weeklyWeightChange: Double? {
        WeightTrend.slopePerDay(WeightTrend.daily(weights)).map { $0 * 7 }
    }

    var latestWeight: Double? {
        if let last = weights.last, last.date > Date.now.addingTimeInterval(-60 * 86_400) {
            return last.kilograms
        }
        let manual = appSettings.manualWeightKilograms
        return manual > 0 ? manual : weights.last?.kilograms
    }

    var age: Int? {
        if profileSettings.birthYear > 0 {
            return Calendar.current.component(.year, from: .now) - profileSettings.birthYear
        }
        return healthBirth.flatMap { EnergyCalculator.age(birth: $0) }
    }

    var heightCm: Double? {
        profileSettings.heightCm > 0 ? profileSettings.heightCm : healthHeightCm
    }

    var sex: BodySex? {
        switch appSettings.sexChoice {
        case .female: .female
        case .male: .male
        case .health: healthSex
        }
    }

    var status: ReproductiveStatus {
        switch appSettings.statusChoice {
        case .none: .none
        case .pregnant: .pregnant
        case .lactating: .lactating
        case .health: healthStatus
        }
    }

    var profile: EnergyProfile {
        EnergyProfile(
            sex: sex,
            age: age,
            heightCm: heightCm,
            weightKg: latestWeight,
            activity: profileSettings.activity,
            goal: profileSettings.goal,
            weeklyRateKg: profileSettings.weeklyRateKg,
            status: status
        )
    }

    /// Today's personalised target, or nil when it is off or the profile is
    /// incomplete.
    var target: EnergyTarget? {
        guard profileSettings.autoTarget else { return nil }
        return EnergyCalculator.target(
            profile: profile,
            exerciseToday: exerciseToday,
            adaptive: profileSettings.adaptive ? adaptiveEstimate : nil
        )
    }

    /// The calorie goal shown today: the personalised one when available.
    func dailyGoal(manual: Int) -> Double {
        target?.calories ?? Double(manual)
    }

    /// Totals of the meals logged in this app today.
    var ownTotals: Nutrients {
        entries.map(\.nutrients).total()
    }

    func start() async {
        guard !started else {
            await refresh()
            return
        }
        started = true
        await requestAccess()
        health.observeChanges {
            Task { @MainActor in await FoodModel.shared.refresh() }
        }
    }

    func requestAccess() async {
        do {
            try await health.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func refresh() async {
        access = health.access
        guard access != .unavailable else { return }
        let today = Date.now
        do {
            entries = try await health.meals(on: today)
        } catch {
            entries = []
        }
        eaten = await health.caloriesEaten(on: today)
        burned = await health.activeCalories(on: today)
        await refreshEnergyInputs(now: today)
    }

    private func refreshEnergyInputs(now: Date) async {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -AdaptiveExpenditure.windowDays, to: startOfToday) ?? startOfToday

        weights = await health.weights(lastDays: 365, now: now)
        healthBirth = health.dateOfBirth()
        healthHeightCm = await health.latestHeightCentimeters()
        healthSex = HealthStore.shared.biologicalSex()
        if appSettings.statusChoice == .health {
            healthStatus = await HealthStore.shared.reproductiveStatus(now: now)
        }

        let workouts = await health.workouts(from: windowStart, to: now)
        let byDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }
        let today = WorkoutDeduplicator.deduplicate(byDay[startOfToday] ?? [])
        workoutsToday = today.kept
        duplicateWorkoutsToday = today.duplicates
        recentWorkouts = WorkoutDeduplicator.sessions(workouts).reversed()

        let intake = await health.dailyIntake(lastDays: AdaptiveExpenditure.windowDays, now: now)
        let days = intake.map { day, kcal in
            DayEnergy(date: day, intake: kcal, exercise: WorkoutDeduplicator.totalCalories(byDay[day] ?? []))
        }
        adaptiveEstimate = AdaptiveExpenditure.estimate(days: days, weights: weights, now: now)
    }

    func logWeight(kilograms: Double, date: Date = .now) async {
        do {
            try await health.logWeight(kilograms: kilograms, date: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func log(name: String, nutrients: Nutrients, date: Date = .now) async {
        do {
            try await health.log(name: name, nutrients: nutrients, date: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    func delete(_ entry: FoodEntry) async {
        do {
            try await health.delete(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
