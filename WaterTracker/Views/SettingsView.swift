import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WaterModel.self) private var model

    @State private var notificationsAllowed = true

    private static let intervals = [15, 20, 30, 45, 60, 90, 120, 180, 240]
    private static let dailyMaximums = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20]

    var body: some View {
        @Bindable var settings = settings
        let unit = settings.unit

        NavigationStack {
            Form {
                Section {
                    Toggle("Calculate automatically", isOn: $settings.autoGoal)
                    if settings.autoGoal {
                        LabeledContent("Today's goal", value: unit.format(settings.dailyGoal))
                        if let breakdown = model.goalBreakdown {
                            ForEach(breakdown.items) { item in
                                LabeledContent(reasonTitle(item.reason), value: item.reason == .body ? unit.format(item.milliliters) : "+\(unit.format(item.milliliters))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Stepper(value: $settings.dailyGoal, in: unit.goalRange, step: unit.goalStep) {
                            LabeledContent("Daily goal", value: unit.format(settings.dailyGoal))
                        }
                    }
                    Picker("Unit", selection: Binding(get: { settings.unit }, set: { settings.changeUnit(to: $0) })) {
                        Text("Milliliters").tag(VolumeUnit.milliliters)
                        Text("Fluid ounces").tag(VolumeUnit.fluidOunces)
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    if settings.autoGoal {
                        Text("Worked out from your body, today's workouts and the options below, and updated whenever you open the app. It is a guide, not medical advice.")
                    }
                }

                if settings.autoGoal {
                    aboutYouSection
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
                        WeekdayPicker(selection: $settings.reminderWeekdays)
                        Picker("At most", selection: $settings.reminderDailyMax) {
                            ForEach(Self.dailyMaximums, id: \.self) { count in
                                Text(count == 0 ? String(localized: "No limit") : String(localized: "\(count) a day"))
                                    .tag(count)
                            }
                        }
                        Toggle("Keep reminding after the goal", isOn: Binding(
                            get: { !settings.remindersStopAtGoal },
                            set: { settings.remindersStopAtGoal = !$0 }
                        ))
                        NavigationLink {
                            ReminderSoundPicker(selection: $settings.reminderSound)
                        } label: {
                            LabeledContent("Sound", value: settings.reminderSound.name)
                        }
                        if !notificationsAllowed {
                            Button("Allow notifications in Settings") { openSystemSettings() }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if settings.reminderWeekdays.isEmpty {
                        Text("Pick at least one day to get reminders.")
                    } else if settings.remindersStopAtGoal {
                        Text("Reminders count from your last drink, stay silent outside these hours, and stop for the day once you reach your goal.")
                    } else {
                        Text("Reminders count from your last drink and stay silent outside these hours.")
                    }
                }

                Section {
                    LabeledContent("Apple Health", value: healthStatus)
                    if model.access == .denied {
                        Button("Open Settings") { openSystemSettings() }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your water is saved in Apple Health, and your settings sync through your own iCloud. This app has no account, no analytics and no servers of its own.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("Based on the open source WaterTracker by Yu Liang, used under the MIT License.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .themedBackground()
            .navigationTitle("Settings")
            .task(id: settings.remindersEnabled) {
                if settings.remindersEnabled {
                    await ReminderScheduler.requestAuthorization()
                }
                notificationsAllowed = await ReminderScheduler.isAuthorized()
            }
        }
    }

    @ViewBuilder
    private var aboutYouSection: some View {
        @Bindable var settings = settings
        Section {
            Picker("Sex", selection: $settings.sexChoice) {
                Text(fromHealth(model.healthSex.map(sexName) ?? String(localized: "not set"))).tag(SexChoice.health)
                Text("Female").tag(SexChoice.female)
                Text("Male").tag(SexChoice.male)
            }
            LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField(weightPlaceholder, value: manualWeight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Workouts today", value: Duration.seconds(model.workoutMinutesToday * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            Toggle("Hot weather or heavy sweating", isOn: $settings.hotWeather)
            if resolvedSex != .male {
                Picker("Pregnancy or breastfeeding", selection: $settings.statusChoice) {
                    Text(fromHealth(statusName(model.healthStatus))).tag(StatusChoice.health)
                    Text("No").tag(StatusChoice.none)
                    Text("Pregnant").tag(StatusChoice.pregnant)
                    Text("Breastfeeding").tag(StatusChoice.lactating)
                }
                Toggle("Adjust for menstrual cycle", isOn: $settings.cycleAdjustment)
                if settings.cycleAdjustment {
                    LabeledContent("Cycle today", value: cycleName)
                }
            }
        } header: {
            Text("About you")
        } footer: {
            Text("Sex, weight, workouts, pregnancy and cycle are read from Apple Health, including what WHOOP or other apps save there. Leave weight empty to use the one in Health. This data is only read and used on this device; just your choices here sync through your iCloud.")
        }
        .task(id: goalInputsKey) {
            await model.updateGoal()
        }
    }

    /// Changes whenever a choice that affects the automatic goal changes.
    private var goalInputsKey: String {
        [
            "\(settings.autoGoal)", settings.sexChoice.rawValue, "\(settings.manualWeightKilograms)",
            "\(settings.hotWeather)", settings.statusChoice.rawValue, "\(settings.cycleAdjustment)",
        ].joined(separator: "|")
    }

    private var resolvedSex: BodySex? {
        switch settings.sexChoice {
        case .health: model.healthSex
        case .female: .female
        case .male: .male
        }
    }

    private var manualWeight: Binding<Double?> {
        let settings = settings
        return Binding(
            get: { settings.manualWeightKilograms > 0 ? settings.manualWeightKilograms : nil },
            set: { settings.manualWeightKilograms = min(max($0 ?? 0, 0), 300) }
        )
    }

    private var weightPlaceholder: String {
        guard let weight = model.healthWeightKilograms else { return String(localized: "Not in Health") }
        return fromHealth(weight.formatted(.number.precision(.fractionLength(0...1))))
    }

    private func fromHealth(_ value: String) -> String {
        String(localized: "From Health (\(value))")
    }

    private func sexName(_ sex: BodySex) -> String {
        switch sex {
        case .female: String(localized: "Female")
        case .male: String(localized: "Male")
        }
    }

    private func statusName(_ status: ReproductiveStatus) -> String {
        switch status {
        case .none: String(localized: "No")
        case .pregnant: String(localized: "Pregnant")
        case .lactating: String(localized: "Breastfeeding")
        }
    }

    private var cycleName: String {
        switch model.cyclePhase {
        case .menstruation?: String(localized: "Period")
        case .luteal?: String(localized: "Luteal phase")
        case .other?: String(localized: "No adjustment")
        case nil: String(localized: "Not enough data")
        }
    }

    private func reasonTitle(_ reason: GoalBreakdown.Reason) -> String {
        switch reason {
        case .body: String(localized: "Body")
        case .activity: String(localized: "Workouts")
        case .heat: String(localized: "Heat")
        case .pregnancy: String(localized: "Pregnancy")
        case .lactation: String(localized: "Breastfeeding")
        case .menstruation: String(localized: "Period")
        case .luteal: String(localized: "Luteal phase")
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

/// One round button per day of the week, in the order the user's region
/// starts the week.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private var calendar: Calendar { .current }

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days")
            HStack(spacing: 0) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    let isOn = selection.contains(weekday)
                    Button {
                        if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                    } label: {
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                            .font(.footnote.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}

/// Lists the reminder sounds. Tapping one chooses it and plays it.
private struct ReminderSoundPicker: View {
    @Binding var selection: ReminderSound

    var body: some View {
        List(ReminderSound.allCases) { sound in
            Button {
                selection = sound
                SoundPreview.play(sound)
            } label: {
                HStack {
                    Text(sound.name)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if sound == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                }
            }
            .accessibilityAddTraits(sound == selection ? .isSelected : [])
        }
        .themedBackground()
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
}
