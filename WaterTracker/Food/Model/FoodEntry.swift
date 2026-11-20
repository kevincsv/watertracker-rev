import Foundation

/// One meal this app saved to the Health app.
nonisolated struct FoodEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let date: Date
    let nutrients: Nutrients
}
