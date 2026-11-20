import SwiftData
import SwiftUI

struct SessionView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Query private var allSets: [WorkoutSet]
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.kg
    @State private var addingExercise = false
    @State private var newExercise = ""

    var body: some View {
        List {
            Section {
                TextField("Nombre", text: $session.title)
                DatePicker("Fecha", selection: $session.date)
            }

            ForEach(session.exercises, id: \.self) { exercise in
                Section {
                    let sets = session.sets(for: exercise)
                    ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                        SetRow(set: set, number: index + 1, unit: unit)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            remove(sets[index])
                        }
                    }
                    Button("Añadir serie", systemImage: "plus") {
                        addSet(to: exercise)
                    }
                } header: {
                    HStack {
                        Text(exercise)
                        Spacer()
                        Menu {
                            Button("Quitar ejercicio", systemImage: "trash", role: .destructive) {
                                removeExercise(exercise)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                } footer: {
                    if let text = lastTimeText(for: exercise) {
                        Text(text)
                    }
                }
            }

            Section {
                Button("Añadir ejercicio", systemImage: "plus.circle.fill") {
                    newExercise = ""
                    addingExercise = true
                }
            }

            Section("Notas") {
                TextField("Cómo fue, máquinas, sensaciones…", text: $session.notes, axis: .vertical)
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .alert("Nuevo ejercicio", isPresented: $addingExercise) {
            TextField("Por ejemplo, press banca", text: $newExercise)
            Button("Añadir") { addExercise() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var history: [SetRecord] {
        allSets.filter { $0.session != session }.map(\.record)
    }

    private func lastTimeText(for exercise: String) -> String? {
        let last = ExerciseHistory.lastSession(of: exercise, in: history, before: session.date)
        guard let first = last.first else { return nil }
        let date = first.sessionDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Última vez (\(date)): \(ExerciseHistory.summary(last, unit: unit))")
    }

    private func addExercise() {
        let name = newExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !session.exercises.contains(name) else { return }
        session.exercises.append(name)
    }

    private func removeExercise(_ exercise: String) {
        for set in session.sets(for: exercise) {
            remove(set)
        }
        session.exercises.removeAll { $0 == exercise }
    }

    /// New sets copy the previous set of this session, or the first set from
    /// last time, so usually only the weight needs a tap.
    private func addSet(to exercise: String) {
        let current = session.sets(for: exercise)
        let template: (reps: Int, weight: Double) = current.last.map { (reps: $0.reps, weight: $0.weightKg) }
            ?? ExerciseHistory.lastSession(of: exercise, in: history, before: session.date)
                .dropFirst(current.count).first.map { (reps: $0.reps, weight: $0.weightKg) }
            ?? (reps: 10, weight: 0)
        let set = WorkoutSet(
            exercise: exercise,
            reps: template.reps,
            weightKg: template.weight,
            order: (session.sets.map(\.order).max() ?? -1) + 1
        )
        context.insert(set)
        session.sets.append(set)
    }

    private func remove(_ set: WorkoutSet) {
        session.sets.removeAll { $0 == set }
        context.delete(set)
    }
}

struct SetRow: View {
    @Bindable var set: WorkoutSet
    let number: Int
    let unit: WeightUnit

    private var weight: Binding<Double> {
        Binding(
            get: { (unit.fromKilograms(set.weightKg) * 10).rounded() / 10 },
            set: { set.weightKg = unit.toKilograms($0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Spacer()
            TextField("0", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
            Text("reps")
                .foregroundStyle(.secondary)
            TextField("0", value: weight, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text(unit.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
        .monospacedDigit()
    }
}
