import SwiftData
import SwiftUI

struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(FoodModel.self) private var food
    @Query(sort: \SavedFood.name) private var savedFoods: [SavedFood]

    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var per100Mode = false
    @State private var gramsText = "100"
    @State private var servings = 1.0
    @State private var date = Date.now
    @State private var saveForLater = true
    @State private var isSaving = false
    @State private var lastFacts: NutritionFacts?
    @State private var estimating = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Values as typed: per serving, or per 100 g.
    private var typed: Nutrients {
        Nutrients(
            kcal: NumberInput.parse(kcalText) ?? 0,
            protein: NumberInput.parse(proteinText) ?? 0,
            carbs: NumberInput.parse(carbsText) ?? 0,
            fat: NumberInput.parse(fatText) ?? 0
        )
    }

    private var grams: Double {
        NumberInput.parse(gramsText) ?? 0
    }

    private var total: Nutrients {
        per100Mode ? typed.scaled(by: grams / 100) : typed.scaled(by: servings)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && total.kcal > 0 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FactsSourceButtons { apply($0) }
                    Button("Describir o fotografiar la comida", systemImage: "sparkles") {
                        estimating = true
                    }
                    if !savedFoods.isEmpty {
                        Menu {
                            ForEach(savedFoods) { saved in
                                Button("\(saved.name) · \(Int(saved.portion.kcal.rounded())) kcal") { fill(from: saved) }
                            }
                        } label: {
                            Label("Elegir de mis comidas", systemImage: "list.bullet")
                        }
                    }
                } header: {
                    Text("Rellenar")
                } footer: {
                    if let note = lastFacts?.note, !note.isEmpty {
                        Text(note)
                    }
                }

                Section("Comida") {
                    TextField("Nombre", text: $name)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Hora", selection: $date, in: ...Date.now.addingTimeInterval(3600))
                }

                Section {
                    Picker("Valores", selection: $per100Mode) {
                        Text("Por ración").tag(false)
                        Text("Por 100 g").tag(true)
                    }
                    .pickerStyle(.segmented)
                    NutrientField(title: "Calorías", unit: "kcal", text: $kcalText)
                    NutrientField(title: "Proteína", unit: "g", text: $proteinText)
                    NutrientField(title: "Carbohidratos", unit: "g", text: $carbsText)
                    NutrientField(title: "Grasa", unit: "g", text: $fatText)
                } footer: {
                    if typed.kcal == 0 && typed.hasMacros {
                        Button("Calcular calorías con los macros (\(Int(typed.kcalFromMacros.rounded())) kcal)") {
                            kcalText = NumberInput.text(typed.kcalFromMacros.rounded())
                        }
                        .font(.footnote)
                    }
                }

                Section {
                    if per100Mode {
                        NutrientField(title: "Cantidad", unit: "g", text: $gramsText)
                    } else {
                        Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                            Text("Raciones: \(servings.formatted(.number.precision(.fractionLength(0...2))))")
                        }
                    }
                    LabeledContent("Total", value: "\(Int(total.kcal.rounded())) kcal")
                }

                Section {
                    Toggle("Guardar en mis comidas", isOn: $saveForLater)
                } footer: {
                    Text("Se guarda en la app Salud. WHOOP la recoge de ahí y la añade a tu Journal.")
                }
            }
            .navigationTitle("Añadir comida")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: per100Mode) { _, _ in
                if let lastFacts { fillNumbers(from: lastFacts) }
            }
            .sheet(isPresented: $estimating) {
                EstimateView { apply($0) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    /// Fills the form from a barcode, a label or an estimate. Labels are
    /// shown per 100 g when that column was read.
    private func apply(_ facts: NutritionFacts) {
        lastFacts = facts
        if let factsName = facts.name, !factsName.isEmpty {
            name = factsName
        }
        if facts.per100 != nil {
            if let size = facts.servingSize {
                gramsText = NumberInput.text(size)
            }
            if per100Mode {
                fillNumbers(from: facts)
            } else {
                per100Mode = true // onChange fills the numbers
            }
        } else {
            servings = 1
            if per100Mode {
                per100Mode = false
            } else {
                fillNumbers(from: facts)
            }
        }
    }

    private func fillNumbers(from facts: NutritionFacts) {
        let values: Nutrients?
        if per100Mode {
            values = facts.per100
        } else if let perServing = facts.perServing {
            values = perServing
        } else if let per100 = facts.per100, let size = facts.servingSize {
            values = per100.scaled(by: size / 100)
        } else {
            values = nil
        }
        guard let values else { return }
        setFields(values)
    }

    private func setFields(_ values: Nutrients) {
        kcalText = NumberInput.text(values.kcal)
        proteinText = NumberInput.text(values.protein)
        carbsText = NumberInput.text(values.carbs)
        fatText = NumberInput.text(values.fat)
    }

    private func fill(from saved: SavedFood) {
        lastFacts = nil
        name = saved.name
        per100Mode = saved.isPer100g
        setFields(saved.nutrients)
        gramsText = NumberInput.text(saved.portionGrams)
        servings = 1
    }

    private func save() async {
        isSaving = true
        let mealName = trimmedName
        await food.log(name: mealName, nutrients: total, date: date)
        if saveForLater {
            remember(mealName)
        }
        dismiss()
    }

    /// Adds the food to "my meals", or updates the one with the same name.
    /// Recipes are left as they are.
    private func remember(_ mealName: String) {
        if let existing = savedFoods.first(where: { ExerciseHistory.key($0.name) == ExerciseHistory.key(mealName) }) {
            if !existing.isRecipe {
                existing.nutrients = typed
                existing.isPer100g = per100Mode
                if per100Mode { existing.portionGrams = grams }
            }
            existing.markUsed()
        } else {
            let saved = SavedFood(name: mealName, nutrients: typed, isPer100g: per100Mode, portionGrams: per100Mode ? grams : 100)
            saved.markUsed()
            context.insert(saved)
        }
    }
}

struct NutrientField: View {
    let title: LocalizedStringKey
    let unit: String
    @Binding var text: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}

#Preview {
    AddFoodView()
        .environment(FoodModel.shared)
        .modelContainer(for: SavedFood.self, inMemory: true)
}
