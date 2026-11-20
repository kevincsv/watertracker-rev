import SwiftData
import SwiftUI

struct FoodView: View {
    @Environment(FoodModel.self) private var food
    @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = SettingsKey.defaultGoal
    @Query(sort: [SortDescriptor(\SavedFood.useCount, order: .reverse), SortDescriptor(\SavedFood.name)])
    private var savedFoods: [SavedFood]
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CalorieSummary(eaten: food.eaten, goal: Double(dailyGoal), burned: food.burned, macros: food.ownTotals)
                }

                if food.access == .unavailable {
                    Section {
                        Text("La app Salud no está disponible en este dispositivo.")
                            .foregroundStyle(.secondary)
                    }
                } else if food.access == .denied {
                    Section {
                        Text("No hay permiso para guardar en Salud. Actívalo en Ajustes > Salud > Acceso a datos y dispositivos > Water Tracker KC.")
                            .foregroundStyle(.secondary)
                    }
                }

                if savedFoods.contains(where: { $0.portion.kcal > 0 }) {
                    Section("Rápido") {
                        ForEach(savedFoods.filter { $0.portion.kcal > 0 }.prefix(5)) { saved in
                            Button {
                                saved.markUsed()
                                Task { await food.log(name: saved.name, nutrients: saved.portion) }
                            } label: {
                                HStack {
                                    Label(saved.name, systemImage: "plus.circle.fill")
                                    Spacer()
                                    Text("\(Int(saved.portion.kcal.rounded())) kcal")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Comidas de hoy") {
                    if food.entries.isEmpty {
                        Text("Todavía no has apuntado nada hoy.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(food.entries) { entry in
                        FoodEntryRow(entry: entry)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { food.entries[$0] }
                        Task {
                            for entry in doomed {
                                await food.delete(entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Comidas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Añadir comida", systemImage: "plus") { showingAdd = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Ajustes de comidas", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFoodView()
            }
            .sheet(isPresented: $showingSettings) {
                FoodSettingsView()
            }
            .task { await food.start() }
            .refreshable { await food.refresh() }
            .alert(
                "No se pudo guardar",
                isPresented: Binding(
                    get: { food.errorMessage != nil },
                    set: { if !$0 { food.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(food.errorMessage ?? "")
            }
        }
    }
}

struct CalorieSummary: View {
    let eaten: Double
    let goal: Double
    let burned: Double
    let macros: Nutrients

    private var remaining: Double { goal - eaten }
    private var progress: Double { goal > 0 ? min(eaten / goal, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(eaten.rounded()))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("de \(Int(goal)) kcal")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(remaining >= 0 ? Color.accentColor : .red)
            Text(remaining >= 0
                 ? String(localized: "Te quedan \(Int(remaining.rounded())) kcal")
                 : String(localized: "Te has pasado \(Int((-remaining).rounded())) kcal"))
                .font(.subheadline)
            if burned > 0 {
                Label("\(Int(burned.rounded())) kcal activas quemadas hoy", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if macros.hasMacros {
                HStack {
                    MacroPill(title: "Proteína", grams: macros.protein)
                    MacroPill(title: "Carbohidratos", grams: macros.carbs)
                    MacroPill(title: "Grasa", grams: macros.fat)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.default, value: eaten)
    }
}

struct MacroPill: View {
    let title: LocalizedStringKey
    let grams: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(grams.rounded())) g")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? String(localized: "Comida") : entry.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.nutrients.kcal.rounded())) kcal")
                .monospacedDigit()
        }
    }

    private var detail: String {
        var parts = [entry.date.formatted(date: .omitted, time: .shortened)]
        let n = entry.nutrients
        if n.hasMacros {
            parts.append(String(localized: "P \(Int(n.protein.rounded())) · C \(Int(n.carbs.rounded())) · G \(Int(n.fat.rounded())) g"))
        }
        return parts.joined(separator: " · ")
    }
}
