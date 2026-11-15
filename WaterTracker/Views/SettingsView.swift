import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WaterModel.self) private var model

    @State private var notificationsAllowed = true

    private static let intervals = [30, 45, 60, 90, 120, 180, 240]

    var body: some View {
        @Bindable var settings = settings
        let unit = settings.unit

        NavigationStack {
            Form {
                Section("Goal") {
                    Stepper(value: $settings.dailyGoal, in: unit.goalRange, step: unit.goalStep) {
                        LabeledContent("Daily goal", value: unit.format(settings.dailyGoal))
                    }
                    Picker("Unit", selection: Binding(get: { settings.unit }, set: { settings.changeUnit(to: $0) })) {
                        Text("Milliliters").tag(VolumeUnit.milliliters)
                        Text("Fluid ounces").tag(VolumeUnit.fluidOunces)
                    }
                }

                Section {
                    ForEach(settings.quickAmounts.indices, id: \.self) { index in
                        Stepper(value: $settings.quickAmounts[index], in: unit.amountRange, step: unit.amountStep) {
                            LabeledContent(String(localized: "Button \(index + 1)"), value: unit.format(settings.quickAmounts[index]))
                        }
                    }
                } header: {
                    Text("Quick amounts")
                } footer: {
                    Text("The first amount is also used by the Log button on reminders.")
                }

                Section {
                    Toggle("Reminders", isOn: $settings.remindersEnabled)
                    if settings.remindersEnabled {
                        Picker("Every", selection: $settings.reminderIntervalMinutes) {
                            ForEach(Self.intervals, id: \.self) { minutes in
                                Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                                    .tag(minutes)
                            }
                        }
                        DatePicker("From", selection: time(\.reminderStartMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: time(\.reminderEndMinutes), displayedComponents: .hourAndMinute)
                        if !notificationsAllowed {
                            Button("Allow notifications in Settings") { openSystemSettings() }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders count from your last drink, stay silent outside these hours, and stop for the day once you reach your goal.")
                }

                Section {
                    LabeledContent("Apple Health", value: healthStatus)
                    if model.access == .denied {
                        Button("Open Settings") { openSystemSettings() }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your water is saved in Apple Health on this device. This app has no account, no analytics and no network connection.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("Based on the open source WaterTracker by Yu Liang, used under the MIT License.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task(id: settings.remindersEnabled) {
                if settings.remindersEnabled {
                    await ReminderScheduler.requestAuthorization()
                }
                notificationsAllowed = await ReminderScheduler.isAuthorized()
            }
        }
    }

    private var healthStatus: String {
        switch model.access {
        case .authorized: String(localized: "Connected")
        case .denied: String(localized: "No access")
        case .notDetermined: String(localized: "Not set up")
        case .unavailable: String(localized: "Not available")
        }
    }

    /// Bridges "minutes after midnight" to the Date a DatePicker needs.
    private func time(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        let settings = settings
        return Binding(
            get: {
                let minutes = settings[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
}
