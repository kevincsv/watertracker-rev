import SwiftData
import SwiftUI

/// A recipe: ingredients with their amounts, divided into servings.
struct RecipeEditor: View {
    @Bindable var food: SavedFood
    @State private var ingredients: [Ingredient] = []
    @State private var addingIngredient = false
    @State private var editing: Ingredient?

    private var total: Nutrients { Recipe.total(ingredients) }
    private var perServing: Nutrients { Recipe.perServing(ingredients, servings: food.recipeServings) }

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $food.name)
                Stepper(value: $food.recipeServings, in: 1...50, step: 1) {
                    Text("Raciones: \(Int(food.recipeServings))")
                }
            }

            Section("Ingredientes") {
                ForEach(ingredients) { ingredient in
                    Button {
                        editing = ingredient
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient.name)
                                    .foregroundStyle(.primary)
                                Text(amountText(ingredient))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(ingredient.total.kcal.rounded())) kcal")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                Button("Añadir ingrediente", systemImage: "plus.circle.fill") {
                    addingIngredient = true
                }
            }

            Section("Por ración") {
                LabeledContent("Calorías", value: "\(Int(perServing.kcal.rounded())) kcal")
                LabeledContent("Proteína", value: "\(Int(perServing.protein.rounded())) g")
                LabeledContent("Carbohidratos", value: "\(Int(perServing.carbs.rounded())) g")
                LabeledContent("Grasa", value: "\(Int(perServing.fat.rounded())) g")
            }

            Section {
                LabeledContent("Receta entera", value: "\(Int(total.kcal.rounded())) kcal")
            }
        }
        .navigationTitle(food.name)
        .onAppear { ingredients = food.ingredients }
        .onChange(of: ingredients) { save() }
        .onChange(of: food.recipeServings) { save() }
        .sheet(isPresented: $addingIngredient) {
            IngredientForm(ingredient: nil) { ingredients.append($0) }
        }
        .sheet(item: $editing) { ingredient in
            IngredientForm(ingredient: ingredient) { updated in
                if let index = ingredients.firstIndex(where: { $0.id == updated.id }) {
                    ingredients[index] = updated
                }
            }
        }
    }

    private func amountText(_ ingredient: Ingredient) -> String {
        let amount = ingredient.amount.formatted(.number.precision(.fractionLength(0...2)))
        return ingredient.isPer100g ? "\(amount) g" : String(localized: "\(amount) ud.")
    }

    private func save() {
        food.ingredients = ingredients
        food.updateFromIngredients()
    }
}

/// Adds or edits one ingredient.
struct IngredientForm: View {
    let ingredient: Ingredient?
    let onSave: (Ingredient) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedFood.name) private var savedFoods: [SavedFood]
    @State private var name = ""
    @State private var per100Mode = true
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var amountText = "100"

    private var nutrients: Nutrients {
        Nutrients(
            kcal: NumberInput.parse(kcalText) ?? 0,
            protein: NumberInput.parse(proteinText) ?? 0,
            carbs: NumberInput.parse(carbsText) ?? 0,
            fat: NumberInput.parse(fatText) ?? 0
        )
    }

    private var amount: Double { NumberInput.parse(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rellenar") {
                    FactsSourceButtons { apply($0) }
                    let plainFoods = savedFoods.filter { !$0.isRecipe }
                    if !plainFoods.isEmpty {
                        Menu {
                            ForEach(plainFoods) { saved in
                                Button(saved.name) { fill(from: saved) }
                            }
                        } label: {
                            Label("Elegir de mis comidas", systemImage: "list.bullet")
                        }
                    }
                }
                Section {
                    TextField("Nombre", text: $name)
                    Picker("Valores", selection: $per100Mode) {
                        Text("Por 100 g").tag(true)
                        Text("Por unidad").tag(false)
                    }
                    .pickerStyle(.segmented)
                    NutrientField(title: "Calorías", unit: "kcal", text: $kcalText)
                    NutrientField(title: "Proteína", unit: "g", text: $proteinText)
                    NutrientField(title: "Carbohidratos", unit: "g", text: $carbsText)
                    NutrientField(title: "Grasa", unit: "g", text: $fatText)
                }
                Section {
                    NutrientField(title: "Cantidad", unit: per100Mode ? "g" : String(localized: "ud."), text: $amountText)
                    LabeledContent("Total", value: "\(Int(nutrients.scaled(by: per100Mode ? amount / 100 : amount).kcal.rounded())) kcal")
                }
            }
            .navigationTitle(ingredient == nil ? "Nuevo ingrediente" : "Ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(Ingredient(
                            id: ingredient?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            nutrients: nutrients,
                            isPer100g: per100Mode,
                            amount: amount
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
            .onAppear {
                guard let ingredient else { return }
                name = ingredient.name
                per100Mode = ingredient.isPer100g
                setFields(ingredient.nutrients)
                amountText = NumberInput.text(ingredient.amount)
            }
        }
    }

    private func apply(_ facts: NutritionFacts) {
        if let factsName = facts.name, !factsName.isEmpty { name = factsName }
        if let per100 = facts.per100 {
            per100Mode = true
            setFields(per100)
        } else if let perServing = facts.perServing {
            per100Mode = false
            setFields(perServing)
            amountText = "1"
        }
    }

    private func fill(from saved: SavedFood) {
        name = saved.name
        per100Mode = saved.isPer100g
        setFields(saved.nutrients)
        amountText = saved.isPer100g ? NumberInput.text(saved.portionGrams) : "1"
    }

    private func setFields(_ values: Nutrients) {
        kcalText = NumberInput.text(values.kcal)
        proteinText = NumberInput.text(values.protein)
        carbsText = NumberInput.text(values.carbs)
        fatText = NumberInput.text(values.fat)
    }
}
