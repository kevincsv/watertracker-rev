import SwiftUI

struct RootView: View {
    @Environment(WaterModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Today", systemImage: "drop.fill") {
                TodayView()
            }
            Tab("Comidas", systemImage: "fork.knife") {
                FoodView()
            }
            Tab("Entrenos", systemImage: "dumbbell.fill") {
                WorkoutsView()
            }
            Tab("History", systemImage: "chart.bar.fill") {
                HistoryView()
            }
            Tab("Friends", systemImage: "person.2.fill") {
                FriendsView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
                let friends = FriendsModel.shared
                if friends.isSharing || !friends.friends.isEmpty {
                    Task { await friends.refresh() }
                }
            }
        }
        .onChange(of: settings.revision) {
            model.settingsChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await model.refresh() }
        }
    }
}

#Preview {
    RootView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
        .environment(FriendsModel.shared)
        .environment(FoodModel.shared)
        .modelContainer(for: FoodStore.models, inMemory: true)
}
