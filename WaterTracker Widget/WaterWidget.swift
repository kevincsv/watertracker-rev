import SwiftUI
import WidgetKit

nonisolated struct WaterTimelineEntry: TimelineEntry, Sendable {
    let date: Date
    let total: Double
    let goal: Double
    let unit: VolumeUnit

    var progress: Double { goal > 0 ? min(total / goal, 1) : 0 }
    var remaining: Double { max(goal - total, 0) }

    static let placeholder = WaterTimelineEntry(date: .now, total: 1250, goal: 2400, unit: .milliliters)
}

/// Reads the snapshot the app saved in the shared container. The widget never
/// touches Apple Health or the network.
nonisolated struct WaterTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterTimelineEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WaterTimelineEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WaterTimelineEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        // A second entry at midnight resets the widget to zero for the new day.
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WaterTimelineEntry {
        let snapshot = DaySnapshot.load()
        return WaterTimelineEntry(date: date, total: snapshot.total(on: date), goal: snapshot.goalMilliliters, unit: snapshot.unit)
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaterWidget", provider: WaterTimelineProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water today")
        .description("Shows how much water you have logged today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(entry.progress, format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Water", systemImage: "drop.fill")
                    .font(.headline)
                Text(entry.unit.format(entry.total))
                Gauge(value: entry.progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        case .accessoryInline:
            Label(entry.unit.format(entry.total), systemImage: "drop.fill")
        case .systemMedium:
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    Text("Water today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.unit.format(entry.total))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(spacing: 8) {
                ring
                Text(entry.unit.format(entry.total))
                    .font(.system(.headline, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var statusText: String {
        entry.remaining > 0
            ? String(localized: "\(entry.unit.format(entry.remaining)) to go")
            : String(localized: "Goal reached")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 9)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .padding(5)
        .accessibilityHidden(true)
    }
}

#Preview(as: .systemSmall) {
    WaterWidget()
} timeline: {
    WaterTimelineEntry.placeholder
}
