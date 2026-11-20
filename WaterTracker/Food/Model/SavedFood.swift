import Foundation
import SwiftData

/// A meal, product or recipe saved to log again quickly.
@Model
final class SavedFood {
    var name: String = ""
    /// Values per serving, or per 100 g when `isPer100g` is true.
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var isPer100g: Bool = false
    /// The amount usually eaten, in grams, for foods stored per 100 g.
    var portionGrams: Double = 100
    /// JSON list of `Ingredient` when this is a recipe.
    var ingredientsData: Data?
    /// How many servings the recipe makes.
    var recipeServings: Double = 1
    var useCount: Int = 0
    var lastUsed: Date = Date.now

    init(name: String, nutrients: Nutrients, isPer100g: Bool = false, portionGrams: Double = 100) {
        self.name = name
        self.kcal = nutrients.kcal
        self.protein = nutrients.protein
        self.carbs = nutrients.carbs
        self.fat = nutrients.fat
        self.isPer100g = isPer100g
        self.portionGrams = portionGrams
    }

    /// Values per serving or per 100 g, as stored.
    var nutrients: Nutrients {
        get { Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    /// What one usual portion contains.
    var portion: Nutrients {
        isPer100g ? nutrients.scaled(by: portionGrams / 100) : nutrients
    }

    var isRecipe: Bool { ingredientsData != nil }

    var ingredients: [Ingredient] {
        get {
            guard let ingredientsData else { return [] }
            return (try? JSONDecoder().decode([Ingredient].self, from: ingredientsData)) ?? []
        }
        set {
            ingredientsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Recalculates the per-serving values of a recipe from its ingredients.
    func updateFromIngredients() {
        nutrients = Recipe.perServing(ingredients, servings: recipeServings)
        isPer100g = false
    }

    func markUsed() {
        useCount += 1
        lastUsed = .now
    }
}

/// One ingredient of a recipe.
nonisolated struct Ingredient: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    /// Values per 100 g when `isPer100g`, otherwise per unit.
    var nutrients: Nutrients
    var isPer100g: Bool
    /// Grams when `isPer100g`, otherwise number of units.
    var amount: Double

    var total: Nutrients {
        nutrients.scaled(by: isPer100g ? amount / 100 : amount)
    }
}

nonisolated enum Recipe {
    static func total(_ ingredients: [Ingredient]) -> Nutrients {
        ingredients.map(\.total).total()
    }

    static func perServing(_ ingredients: [Ingredient], servings: Double) -> Nutrients {
        total(ingredients).scaled(by: 1 / max(servings, 1))
    }
}
