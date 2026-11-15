import AppIntents

/// Lets Siri and the Shortcuts app log water. Runs inside the app, on device.
nonisolated struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Logs water to Apple Health.")
    static let openAppWhenRun = false

    @Parameter(title: "Amount", description: "In your chosen unit. Leave empty to use your first quick amount.")
    var amount: Double?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings.shared
        let milliliters = amount.map { settings.unit.milliliters(from: $0) }
            ?? settings.quickAmounts.first
            ?? settings.unit.defaultQuickAmounts[0]

        guard await WaterModel.shared.log(milliliters) else {
            return .result(dialog: "Could not save to Apple Health.")
        }
        let logged = settings.unit.format(milliliters)
        let total = settings.unit.format(WaterModel.shared.todayTotal)
        return .result(dialog: "Logged \(logged). Today's total is \(total).")
    }
}

nonisolated struct WaterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a drink in \(.applicationName)"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
    }
}
