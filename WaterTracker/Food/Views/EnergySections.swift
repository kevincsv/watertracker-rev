import SwiftUI

/// Target breakdown, today's workouts and weight, shown under the calorie
/// summary.
struct EnergySections: View {
    @Binding var showProfile: Bool
    @Environment(FoodModel.self) private var food
    @State private var profileSettings = FoodProfileSettings.shared
    @State private var loggingWeight = false

    var body: some View {
        if profileSettings.autoTarget {
            if let target = food.target {
                Section {
                    DisclosureGroup {
                        TargetBreakdown(target: target)
                    } label: {
                        Label("Cómo se calcula tu objetivo", systemImage: "function")
                    }
                }
            } else {
                Section {
                    Button {
                        showProfile = true
                    } label: {
                        Label("Completa tu perfil para calcular tus calorías", systemImage: "person.crop.circle.badge.questionmark")
                    }
                } footer: {
                    Text("Hace falta sexo, edad, altura y peso. Si están en la app Salud se usan solos.")
                }
            }
        }

        Section {
            if food.workoutsToday.isEmpty {
                Text("Sin entrenos hoy en Salud.")
                    .foregroundStyle(.secondary)
            }
            ForEach(food.workoutsToday) { workout in
                WorkoutRow(workout: workout)
            }
        } header: {
            Text("Entrenos de hoy")
        } footer: {
            if !food.duplicateWorkoutsToday.isEmpty {
                Text("\(food.duplicateWorkoutsToday.count) entrenos duplicados ignorados: \(duplicateText). Cuando dos apps graban la misma sesión, solo cuenta la de más calorías.")
            } else if !food.workoutsToday.isEmpty {
                Text("Las calorías de los entrenos se suman a tu objetivo de hoy.")
            }
        }

        Section("Peso") {
            NavigationLink {
                WeightView()
            } label: {
                WeightSummaryRow(trend: food.weightTrend.last?.kilograms, weeklyChange: food.weeklyWeightChange)
            }
            Button("Apuntar peso", systemImage: "scalemass") {
                loggingWeight = true
            }
        }
        .sheet(isPresented: $loggingWeight) {
            LogWeightView(initial: food.weights.last?.kilograms ?? food.latestWeight)
        }
    }

    private var duplicateText: String {
        food.duplicateWorkoutsToday.map { "\($0.activity) (\($0.source))" }.joined(separator: ", ")
    }
}

struct TargetBreakdown: View {
    let target: EnergyTarget

    var body: some View {
        LabeledContent("Metabolismo basal", value: kcal(target.bmr))
        LabeledContent("Gasto sin entrenos (fórmula)", value: kcal(target.formulaBaseline))
        if let adaptive = target.adaptiveBaseline {
            LabeledContent("Gasto sin entrenos (tu peso real)", value: kcal(adaptive))
            LabeledContent("Peso del ajuste adaptativo", value: target.adaptiveWeight.formatted(.percent.precision(.fractionLength(0))))
        }
        LabeledContent("Gasto base usado", value: kcal(target.baseline))
        LabeledContent("Entrenos de hoy", value: signed(target.exercise))
        if target.goalAdjustment != 0 {
            LabeledContent("Objetivo de peso", value: signed(target.goalAdjustment))
        }
        if target.statusExtra > 0 {
            LabeledContent("Embarazo o lactancia", value: signed(target.statusExtra))
        }
        LabeledContent("Objetivo de hoy", value: kcal(target.calories))
            .bold()
        if target.floorApplied {
            Text("Se ha subido al mínimo recomendado para no comer demasiado poco.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if target.adaptiveBaseline == nil {
            Text("Con 2 o 3 semanas de comidas y pesos apuntados, el objetivo se ajustará a cómo cambia tu peso de verdad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func kcal(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    private func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded) kcal" : "\(rounded) kcal"
    }
}

struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activity)
                Text("\(workout.source) · \(workout.start.formatted(date: .omitted, time: .shortened)) · \(Int((workout.duration / 60).rounded())) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(Int(workout.kcal.rounded())) kcal")
                .monospacedDigit()
                .foregroundStyle(Theme.good)
        }
    }
}

struct WeightSummaryRow: View {
    let trend: Double?
    let weeklyChange: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let trend {
                    Text("\(trend.formatted(.number.precision(.fractionLength(1)))) kg")
                        .font(Theme.number(28))
                    Text("Peso de tendencia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sin pesos todavía")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let weeklyChange {
                Text(changeText(weeklyChange))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changeText(_ change: Double) -> String {
        let value = change.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        return String(localized: "\(value) kg/semana")
    }
}
