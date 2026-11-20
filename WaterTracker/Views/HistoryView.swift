import Charts
import SwiftUI

struct HistoryView: View {
    @Environment(WaterModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var range: HistoryRange = .week

    enum HistoryRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            }
        }
    }

    private var days: [DayTotal] { Array(model.history.suffix(range.rawValue)) }

    var body: some View {
        let unit = settings.unit
        let goal = settings.dailyGoal
        let stats = HistoryStats(days: days, allDays: model.history, goal: goal)

        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(HistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if days.isEmpty {
                        ContentUnavailableView(
                            "No data yet",
                            systemImage: "chart.bar",
                            description: Text("Log some water and your history will appear here.")
                        )
                    } else {
                        Chart {
                            ForEach(days) { day in
                                BarMark(
                                    x: .value("Day", day.date, unit: .day),
                                    y: .value("Amount", unit.value(fromMilliliters: day.milliliters))
                                )
                                .foregroundStyle(day.milliliters >= goal ? Theme.good : Color.accentColor)
                                .cornerRadius(4)
                            }
                            RuleMark(y: .value("Goal", unit.value(fromMilliliters: goal)))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("Goal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .frame(height: 240)
                        .padding(.vertical, 8)
                        .accessibilityLabel(Text("Water per day"))
                    }
                }

                Section("Summary") {
                    LabeledContent("Daily average", value: unit.format(stats.average))
                    LabeledContent("Days goal met", value: String(localized: "\(stats.daysMet) of \(days.count)"))
                    LabeledContent("Current streak", value: String(localized: "\(stats.streak) days"))
                }
            }
            .themedBackground()
            .navigationTitle("History")
            .refreshable { await model.refresh() }
        }
    }
}

/// Numbers shown under the chart.
nonisolated struct HistoryStats: Sendable {
    let average: Double
    let daysMet: Int
    let streak: Int

    /// `days` is the visible range and `allDays` everything loaded; both are
    /// oldest first and end today.
    init(days: [DayTotal], allDays: [DayTotal], goal: Double) {
        average = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.milliliters } / Double(days.count)
        daysMet = days.count(where: { $0.milliliters >= goal })

        // Today only counts once the goal is met, so an unfinished day does
        // not break a streak.
        var remaining = allDays[...]
        if let today = remaining.last, today.milliliters < goal {
            remaining = remaining.dropLast()
        }
        var count = 0
        for day in remaining.reversed() {
            guard day.milliliters >= goal else { break }
            count += 1
        }
        streak = count
    }
}

#Preview {
    HistoryView()
        .environment(AppSettings.shared)
        .environment(WaterModel.shared)
}
