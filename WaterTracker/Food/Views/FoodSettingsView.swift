import SwiftUI

struct FoodSettingsView: View {
    @Environment(FoodModel.self) private var food
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = SettingsKey.defaultGoal

    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo diario") {
                    Stepper(value: $dailyGoal, in: 1000...6000, step: 50) {
                        Text("\(dailyGoal) kcal")
                    }
                }

                Section("Comidas") {
                    NavigationLink("Mis comidas") { SavedFoodsView() }
                }

                Section {
                    Button("Pedir permiso a Salud") {
                        Task { await food.requestAccess() }
                    }
                } header: {
                    Text("Salud y WHOOP")
                } footer: {
                    Text("Las comidas se guardan en la app Salud con calorías, proteína, carbohidratos y grasa. Para que WHOOP las lea, en la app Salud ve a Compartir > Apps > WHOOP y activa la lectura de nutrición.")
                }

                Section("Privacidad") {
                    Text("Las comidas solo van a la app Salud. Tus comidas guardadas, recetas, rutinas y entrenos se quedan en este iPhone, sin iCloud. Para los códigos de barras solo se envía el número del código a Open Food Facts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes de comidas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
