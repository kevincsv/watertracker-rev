import SwiftUI
import UserNotifications

@main
struct WaterTrackerApp: App {
    @State private var settings = AppSettings.shared
    @State private var model = WaterModel.shared

    init() {
        // Must be set before launch finishes so notification actions are delivered.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(model)
        }
    }
}
