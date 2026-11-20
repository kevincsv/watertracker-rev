import HealthKit

nonisolated enum WorkoutNames {
    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            String(localized: "Fuerza")
        case .running: String(localized: "Carrera")
        case .walking: String(localized: "Caminata")
        case .cycling: String(localized: "Bici")
        case .swimming: String(localized: "Natación")
        case .highIntensityIntervalTraining: String(localized: "HIIT")
        case .yoga: String(localized: "Yoga")
        case .pilates: String(localized: "Pilates")
        case .rowing: String(localized: "Remo")
        case .elliptical: String(localized: "Elíptica")
        case .stairClimbing, .stairs: String(localized: "Escaleras")
        case .boxing, .kickboxing: String(localized: "Boxeo")
        case .coreTraining: String(localized: "Core")
        case .mixedCardio, .cardioDance: String(localized: "Cardio")
        case .crossTraining: String(localized: "Entrenamiento cruzado")
        case .soccer: String(localized: "Fútbol")
        case .tennis, .squash, .badminton, .tableTennis: String(localized: "Raqueta")
        default: String(localized: "Entreno")
        }
    }
}
