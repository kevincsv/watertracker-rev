import SwiftUI

/// Workouts that reached the Health app from WHOOP, an Apple Watch, the
/// iPhone or any other app. They are the same ones the calorie target uses,
/// with sessions recorded by more than one app shown once.
struct HealthWorkoutsSection: View {
    @Environment(FoodModel.self) private var food
    static let previewCount = 5

    var body: some View {
        Section {
            if food.access == .unavailable {
                Text("La app Salud no está disponible en este dispositivo.")
                    .foregroundStyle(.secondary)
            } else if food.recentWorkouts.isEmpty {
                Text("Aquí aparecerán los entrenos de WHOOP, Apple Watch u otras apps en cuanto lleguen a Salud.")
                    .foregroundStyle(.secondary)
            }
            ForEach(food.recentWorkouts.prefix(Self.previewCount)) { group in
                HealthWorkoutRow(group: group)
            }
            if food.recentWorkouts.count > Self.previewCount {
                NavigationLink("Ver todos (\(food.recentWorkouts.count))") {
                    HealthWorkoutsList()
                }
            }
        } header: {
            Text("De Salud")
        } footer: {
            if !food.recentWorkouts.isEmpty {
                Text("Últimas 4 semanas. Si WHOOP y el reloj graban la misma sesión, sale una sola vez y cuenta la de más calorías. Si WHOOP la sube más tarde, aparece y se ajusta sola.")
            }
        }
    }
}

struct HealthWorkoutsList: View {
    @Environment(FoodModel.self) private var food

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(food.recentWorkouts.filter { Calendar.current.isDate($0.kept.start, inSameDayAs: day) }) { group in
                        HealthWorkoutRow(group: group)
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("De Salud")
        .refreshable { await food.refresh() }
    }

    private var days: [Date] {
        var seen: Set<Date> = []
        return food.recentWorkouts
            .map { Calendar.current.startOfDay(for: $0.kept.start) }
            .filter { seen.insert($0).inserted }
    }
}

struct HealthWorkoutRow: View {
    let group: WorkoutSessionGroup

    private var workout: WorkoutRecord { group.kept }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activity)
                Text("\(workout.source) · \(when) · \(Int((workout.duration / 60).rounded())) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !group.otherSources.isEmpty {
                    Label("También en \(group.otherSources.formatted(.list(type: .and)))", systemImage: "square.on.square")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if workout.kcal > 0 {
                Text("\(Int(workout.kcal.rounded())) kcal")
                    .monospacedDigit()
                    .foregroundStyle(Theme.good)
            }
        }
    }

    private var when: String {
        if Calendar.current.isDateInToday(workout.start) {
            return workout.start.formatted(date: .omitted, time: .shortened)
        }
        return workout.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
