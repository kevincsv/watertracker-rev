import SwiftData
import SwiftUI
import UserNotifications

@main
struct WaterTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings.shared
    @State private var model = WaterModel.shared
    @State private var friends = FriendsModel.shared
    @State private var food = FoodModel.shared
    private let foodContainer = FoodStore.makeContainer()

    init() {
        // Must be set before launch finishes so notification actions are delivered.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(model)
                .environment(friends)
                .environment(food)
                .tint(Theme.accent)
        }
        .modelContainer(foodContainer)
    }
}
