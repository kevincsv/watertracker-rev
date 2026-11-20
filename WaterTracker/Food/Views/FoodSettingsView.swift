import SwiftUI

struct FoodSettingsView: View {
    @Environment(FoodModel.self) private var food
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = SettingsKey.defaultGoal
    @Bindable private var profile = FoodProfileSettings.shared
    @Bindable private var appSettings = AppSettings.shared

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    /// Edits the age, stored as a birth year so it stays right over time.
    private var age: Binding<Int> {
        Binding(
            get: { food.age ?? 30 },
            set: { profile.birthYear = currentYear - $0 }
        )
    }

    private var height: Binding<Double> {
        Binding(
            get: { (food.heightCm ?? 170).rounded() },
            set: { profile.heightCm = $0 }
        )
    }

    private func sexName(_ sex: BodySex) -> String {
        switch sex {
        case .female: String(localized: "Mujer (de Salud)")
        case .male: String(localized: "Hombre (de Salud)")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Calcular mi objetivo", isOn: $profile.autoTarget)
                    if profile.autoTarget {
                        if let target = food.target {
                            LabeledContent("Hoy", value: "\(Int(target.calories)) kcal")
                        }
                        Toggle("Ajustar con mi peso real", isOn: $profile.adaptive)
                    } else {
                        Stepper(value: $dailyGoal, in: 1000...6000, step: 50) {
                            Text("\(dailyGoal) kcal")
                        }
                    }
                } header: {
                    Text("Objetivo diario")
                } footer: {
                    if profile.autoTarget {
                        Text("Mifflin-St Jeor con tu sexo, edad, altura y peso, por tu actividad sin entrenos, más las calorías de los entrenos de hoy en Salud (sin duplicados). El ajuste con tu peso real compara lo que comes con tu tendencia de peso.")
                    }
                }

                if profile.autoTarget {
                    Section("Perfil") {
                        Picker("Sexo", selection: $appSettings.sexChoice) {
                            Text(food.healthSex.map(sexName) ?? String(localized: "De la app Salud")).tag(SexChoice.health)
                            Text("Mujer").tag(SexChoice.female)
                            Text("Hombre").tag(SexChoice.male)
                        }
                        Stepper(value: age, in: 14...100) {
                            LabeledContent("Edad", value: food.age.map { String(localized: "\($0) años") } ?? String(localized: "Sin datos"))
                        }
                        Stepper(value: height, in: 120...230) {
                            LabeledContent("Altura", value: food.heightCm.map { "\(Int($0.rounded())) cm" } ?? String(localized: "Sin datos"))
                        }
                        LabeledContent("Peso", value: food.latestWeight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? String(localized: "Apúntalo en Comidas > Peso"))
                        Picker("Embarazo o lactancia", selection: $appSettings.statusChoice) {
                            Text("De la app Salud").tag(StatusChoice.health)
                            Text("No").tag(StatusChoice.none)
                            Text("Embarazo").tag(StatusChoice.pregnant)
                            Text("Lactancia").tag(StatusChoice.lactating)
                        }
                    }

                    Section {
                        Picker("Actividad sin entrenos", selection: $profile.activity) {
                            Text("Sedentaria (oficina, poco caminar)").tag(ActivityLevel.sedentary)
                            Text("Ligera (de pie o caminando a ratos)").tag(ActivityLevel.light)
                            Text("Moderada (trabajo activo)").tag(ActivityLevel.moderate)
                            Text("Alta (trabajo físico)").tag(ActivityLevel.high)
                        }
                        Picker("Objetivo", selection: $profile.goal) {
                            Text("Perder peso").tag(WeightGoal.lose)
                            Text("Mantener").tag(WeightGoal.maintain)
                            Text("Ganar peso").tag(WeightGoal.gain)
                        }
                        if profile.goal != .maintain {
                            Picker("Ritmo", selection: $profile.weeklyRateKg) {
                                Text("0,25 kg/semana").tag(0.25)
                                Text("0,5 kg/semana").tag(0.5)
                                Text("0,75 kg/semana").tag(0.75)
                                Text("1 kg/semana").tag(1.0)
                            }
                        }
                    } header: {
                        Text("Actividad y objetivo")
                    } footer: {
                        Text("El sexo y el embarazo son los mismos que usa la meta automática del agua. La edad y la altura salen de la app Salud si están ahí; si las cambias aquí, se usan las tuyas.")
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
            .themedBackground()
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
