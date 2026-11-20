import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var addingRoutine = false
    @State private var newName = ""

    var body: some View {
        List {
            if routines.isEmpty {
                Text("Crea rutinas como \"Pierna\" o \"Empuje\" con sus ejercicios, y empieza el entreno desde ellas.")
                    .foregroundStyle(.secondary)
            }
            ForEach(routines) { routine in
                NavigationLink {
                    RoutineEditor(routine: routine)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name)
                        Text(routine.exercises.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(routines[index])
                }
            }
        }
        .themedBackground()
        .navigationTitle("Rutinas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva rutina", systemImage: "plus") {
                    newName = ""
                    addingRoutine = true
                }
            }
        }
        .alert("Nueva rutina", isPresented: $addingRoutine) {
            TextField("Nombre", text: $newName)
            Button("Crear") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    context.insert(Routine(name: name))
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

struct RoutineEditor: View {
    @Bindable var routine: Routine
    @State private var newExercise = ""

    var body: some View {
        List {
            Section {
                TextField("Nombre", text: $routine.name)
            }
            Section("Ejercicios") {
                ForEach(routine.exercises, id: \.self) { exercise in
                    Text(exercise)
                }
                .onDelete { routine.exercises.remove(atOffsets: $0) }
                .onMove { routine.exercises.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("Añadir ejercicio", text: $newExercise)
                        .onSubmit(add)
                    Button("Añadir", systemImage: "plus.circle.fill", action: add)
                        .labelStyle(.iconOnly)
                        .disabled(newExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .themedBackground()
        .navigationTitle(routine.name)
        .toolbar { EditButton() }
    }

    private func add() {
        let name = newExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !routine.exercises.contains(name) else { return }
        routine.exercises.append(name)
        newExercise = ""
    }
}
