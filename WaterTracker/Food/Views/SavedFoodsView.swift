import SwiftData
import SwiftUI

struct SavedFoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedFood.name) private var savedFoods: [SavedFood]
    @State private var newRecipe: SavedFood?

    var body: some View {
        List {
            if savedFoods.isEmpty {
                Text("Aquí aparecen las comidas que guardas al añadirlas y tus recetas.")
                    .foregroundStyle(.secondary)
            }
            ForEach(savedFoods) { saved in
                NavigationLink {
                    if saved.isRecipe {
                        RecipeEditor(food: saved)
                    } else {
                        SavedFoodEditor(food: saved)
                    }
                } label: {
                    SavedFoodRow(food: saved)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(savedFoods[index])
                }
            }
        }
        .themedBackground()
        .navigationTitle("Mis comidas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva receta", systemImage: "plus") {
                    let recipe = SavedFood(name: String(localized: "Receta nueva"), nutrients: .zero)
                    recipe.ingredients = []
                    context.insert(recipe)
                    newRecipe = recipe
                }
            }
        }
        .navigationDestination(item: $newRecipe) { recipe in
            RecipeEditor(food: recipe)
        }
    }
}

struct SavedFoodRow: View {
    let food: SavedFood

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if food.isRecipe {
                    Image(systemName: "frying.pan")
                        .foregroundStyle(.secondary)
                }
                Text(food.name)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let n = food.portion
        var text = String(localized: "\(Int(n.kcal.rounded())) kcal · P \(Int(n.protein.rounded())) · C \(Int(n.carbs.rounded())) · G \(Int(n.fat.rounded())) g")
        if food.isPer100g {
            text += " · \(Int(food.portionGrams.rounded())) g"
        } else if food.isRecipe {
            text += String(localized: " por ración")
        }
        return text
    }
}

/// Edits a saved food that is not a recipe.
struct SavedFoodEditor: View {
    @Bindable var food: SavedFood
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var gramsText = ""

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $food.name)
            }
            Section(food.isPer100g ? LocalizedStringKey("Por 100 g") : LocalizedStringKey("Por ración")) {
                NutrientField(title: "Calorías", unit: "kcal", text: $kcalText)
                NutrientField(title: "Proteína", unit: "g", text: $proteinText)
                NutrientField(title: "Carbohidratos", unit: "g", text: $carbsText)
                NutrientField(title: "Grasa", unit: "g", text: $fatText)
            }
            if food.isPer100g {
                Section {
                    NutrientField(title: "Ración habitual", unit: "g", text: $gramsText)
                }
            }
        }
        .themedBackground()
        .navigationTitle(food.name)
        .onAppear {
            kcalText = NumberInput.text(food.kcal)
            proteinText = NumberInput.text(food.protein)
            carbsText = NumberInput.text(food.carbs)
            fatText = NumberInput.text(food.fat)
            gramsText = NumberInput.text(food.portionGrams)
        }
        .onChange(of: [kcalText, proteinText, carbsText, fatText, gramsText]) {
            food.nutrients = Nutrients(
                kcal: NumberInput.parse(kcalText) ?? 0,
                protein: NumberInput.parse(proteinText) ?? 0,
                carbs: NumberInput.parse(carbsText) ?? 0,
                fat: NumberInput.parse(fatText) ?? 0
            )
            if let grams = NumberInput.parse(gramsText), grams > 0 {
                food.portionGrams = grams
            }
        }
    }
}
