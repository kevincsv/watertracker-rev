import SwiftData
import SwiftUI

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var path: [WorkoutSession] = []
    @AppStorage(SettingsKey.weightUnit) private var weightUnit = WeightUnit.kg

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink {
                        RoutinesView()
                    } label: {
                        Label("Rutinas", systemImage: "list.bullet.clipboard")
                    }
                    Picker("Unidad de peso", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                }

                Section("Historial") {
                    if sessions.isEmpty {
                        Text("Pulsa + para empezar un entreno. Puedes partir de una rutina o hacerlo libre.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(sessions[index])
                        }
                    }
                }
            }
            .navigationTitle("Entrenos")
            .navigationDestination(for: WorkoutSession.self) { session in
                SessionView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Entreno libre", systemImage: "figure.strengthtraining.traditional") {
                            start(from: nil)
                        }
                        if !routines.isEmpty {
                            Section("Rutinas") {
                                ForEach(routines) { routine in
                                    Button(routine.name) { start(from: routine) }
                                }
                            }
                        }
                    } label: {
                        Label("Empezar entreno", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func start(from routine: Routine?) {
        let session = WorkoutSession(
            title: routine?.name ?? String(localized: "Entreno"),
            exercises: routine?.exercises ?? []
        )
        context.insert(session)
        path.append(session)
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let date = session.date.formatted(date: .abbreviated, time: .shortened)
        let exercises = Set(session.sets.map(\.exercise)).count
        return String(localized: "\(date) · \(exercises) ejercicios · \(session.sets.count) series")
    }
}

#Preview {
    WorkoutsView()
        .modelContainer(for: [Routine.self, WorkoutSession.self, WorkoutSet.self], inMemory: true)
}
