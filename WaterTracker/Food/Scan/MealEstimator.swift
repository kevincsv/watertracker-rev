import Foundation
import FoundationModels

/// What the on-device model returns for one meal.
@Generable
nonisolated struct MealEstimate {
    @Guide(description: "Short name for the meal, in Spanish")
    var name: String
    @Guide(description: "Total kilocalories for the whole meal as described")
    var kcal: Double
    @Guide(description: "Total protein in grams")
    var protein: Double
    @Guide(description: "Total carbohydrates in grams")
    var carbs: Double
    @Guide(description: "Total fat in grams")
    var fat: Double
    @Guide(description: "One short line in Spanish with the portion sizes assumed")
    var assumptions: String
}

/// Estimates calories and macros from a description, using the language
/// model built into the device. Nothing leaves the iPhone.
nonisolated enum MealEstimator {
    nonisolated enum EstimateError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            }
        }
    }

    /// Why estimates are not possible on this device, or nil when they are.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return String(localized: "Este iPhone no tiene Apple Intelligence, que hace falta para estimar comidas.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Activa Apple Intelligence en Ajustes para estimar comidas.")
        case .unavailable(.modelNotReady):
            return String(localized: "El modelo de Apple Intelligence aún se está descargando. Prueba más tarde.")
        case .unavailable:
            return String(localized: "Apple Intelligence no está disponible ahora mismo.")
        }
    }

    /// - Parameters:
    ///   - description: What the user typed, in any language.
    ///   - photoLabels: Objects recognised in a photo of the meal, if any.
    static func estimate(description: String, photoLabels: [String] = []) async throws -> NutritionFacts {
        if let reason = unavailableReason {
            throw EstimateError.unavailable(reason)
        }
        let session = LanguageModelSession(instructions: """
            You are a nutrition assistant for a calorie tracker used in the United Kingdom. \
            Estimate the calories and macronutrients of the meal the user describes. \
            Assume typical UK portion sizes when none are given. Give realistic totals \
            for everything described, not per 100 g. Answer the text fields in Spanish.
            """)
        var prompt = ""
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            prompt += "Meal: \(trimmed)\n"
        }
        if !photoLabels.isEmpty {
            prompt += "An image classifier saw these things in a photo of the meal, most likely first: \(photoLabels.joined(separator: ", ")). Ignore labels that are not food.\n"
        }
        let response = try await session.respond(to: prompt, generating: MealEstimate.self)
        let estimate = response.content
        return NutritionFacts(
            name: estimate.name,
            per100: nil,
            perServing: Nutrients(
                kcal: max(0, estimate.kcal.rounded()),
                protein: max(0, estimate.protein.rounded()),
                carbs: max(0, estimate.carbs.rounded()),
                fat: max(0, estimate.fat.rounded())
            ),
            servingSize: nil,
            note: estimate.assumptions
        )
    }
}
