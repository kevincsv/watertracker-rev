import Charts
import SwiftUI

/// Weigh-ins and the smoothed trend.
struct WeightView: View {
    @Environment(FoodModel.self) private var food
    @State private var range = 90
    @State private var loggingWeight = false

    private var start: Date { Date.now.addingTimeInterval(-Double(range) * 86_400) }
    private var raw: [WeightPoint] { WeightTrend.daily(food.weights).filter { $0.date >= start } }
    private var trend: [WeightPoint] { food.weightTrend.filter { $0.date >= start } }

    var body: some View {
        List {
            Section {
                Picker("Periodo", selection: $range) {
                    Text("30 días").tag(30)
                    Text("90 días").tag(90)
                    Text("1 año").tag(365)
                }
                .pickerStyle(.segmented)

                if raw.isEmpty {
                    Text("Apunta tu peso unos días para ver la tendencia. Mejor por la mañana, siempre en las mismas condiciones.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(raw) { point in
                            PointMark(
                                x: .value("Fecha", point.date, unit: .day),
                                y: .value("Peso", point.kilograms)
                            )
                            .foregroundStyle(.secondary)
                            .symbolSize(20)
                        }
                        ForEach(trend) { point in
                            LineMark(
                                x: .value("Fecha", point.date, unit: .day),
                                y: .value("Tendencia", point.kilograms)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .frame(height: 240)
                }
            } footer: {
                Text("Los puntos son tus pesajes. La línea es la tendencia, que suaviza los cambios de agua del día a día.")
            }

            Section {
                WeightSummaryRow(trend: food.weightTrend.last?.kilograms, weeklyChange: food.weeklyWeightChange)
                Button("Apuntar peso", systemImage: "scalemass") { loggingWeight = true }
            }

            if !raw.isEmpty {
                Section("Pesajes") {
                    ForEach(raw.reversed()) { point in
                        LabeledContent(
                            point.date.formatted(date: .abbreviated, time: .omitted),
                            value: "\(point.kilograms.formatted(.number.precision(.fractionLength(1)))) kg"
                        )
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Peso")
        .sheet(isPresented: $loggingWeight) {
            LogWeightView(initial: food.weights.last?.kilograms ?? food.latestWeight)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = raw.map(\.kilograms) + trend.map(\.kilograms)
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        return (low - 1)...(high + 1)
    }
}

/// Saves a weigh-in to the Health app.
struct LogWeightView: View {
    let initial: Double?
    @Environment(FoodModel.self) private var food
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NutrientField(title: "Peso", unit: "kg", text: $text)
                    DatePicker("Fecha", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Se guarda en la app Salud.")
                }
            }
            .themedBackground()
            .navigationTitle("Apuntar peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let kilograms = NumberInput.parse(text) else { return }
                        Task {
                            await food.logWeight(kilograms: kilograms, date: date)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let initial { text = NumberInput.text(initial) }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        guard let value = NumberInput.parse(text) else { return false }
        return (25...350).contains(value)
    }
}
