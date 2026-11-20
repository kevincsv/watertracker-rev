import Charts
import SwiftUI

/// The Body tab: a 3D figure shaped by the scale's trends, the numbers behind
/// it, and a chart per measurement.
struct BodyView: View {
    @State private var model = BodyModel.shared
    /// Days back from today that the figure shows (0 = today).
    @State private var daysBack = 0.0
    @State private var compareDays = 0
    @State private var chartMetric = BodyMetric.weight
    @State private var showingWithings = false

    private var shownDate: Date {
        Calendar.current.date(byAdding: .day, value: -Int(daysBack.rounded()), to: .now) ?? .now
    }

    private var historyDays: Double {
        guard let first = model.firstDate else { return 0 }
        return max(Date.now.timeIntervalSince(first) / 86_400, 0).rounded(.down)
    }

    var body: some View {
        NavigationStack {
            List {
                if model.readings.isEmpty {
                    emptySection
                } else {
                    figureSection
                    statsSection
                    analysisSection
                    chartSection
                }
                sourcesSection
            }
            .themedBackground()
            .navigationTitle("Body")
            .refreshable { await model.reload(forceWithings: true) }
            .task { await model.reload() }
            .sheet(isPresented: $showingWithings) {
                WithingsSettingsView()
            }
        }
    }

    // MARK: Sections

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text("See your body composition")
                    .font(.headline)
                Text("Weigh yourself on a smart scale such as Withings. Its weight, body fat and lean mass reach the Health app, and this tab turns them into trends and a 3D model. Connect your Withings account to add muscle, water, bone and visceral fat.")
                    .foregroundStyle(.secondary)
                if !model.hasAskedHealth {
                    Button("Read from the Health app") {
                        Task { await model.requestHealthAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var figureSection: some View {
        Section {
            VStack(spacing: 12) {
                let ghost: BodyShape? = compareDays > 0
                    ? model.shape(at: shownDate.addingTimeInterval(-Double(compareDays) * 86_400))
                    : nil
                Body3DView(shape: model.shape(at: shownDate), ghost: ghost)
                    .frame(height: 420)
                    .background(
                        RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 260)
                    )

                if historyDays >= 2 {
                    VStack(spacing: 4) {
                        Slider(value: $daysBack, in: 0...historyDays, step: 1) {
                            Text("Date")
                        }
                        .environment(\.layoutDirection, .rightToLeft)
                        Text(daysBack < 0.5 ? String(localized: "Today") : shownDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Compare with", selection: $compareDays) {
                    Text("No comparison").tag(0)
                    Text("1 month before").tag(30)
                    Text("3 months before").tag(90)
                    Text("1 year before").tag(365)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if compareDays > 0 {
                    Label("The outline is your body then.", systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("The figure follows your trend, not single weigh-ins. Fat widens the waist and belly, and muscle the shoulders, arms and legs.")
        }
    }

    private var statsSection: some View {
        Section("Now") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(model.availableMetrics) { metric in
                    if let value = model.trendValue(metric, at: shownDate) {
                        MetricTile(metric: metric, value: value, weeklyRate: daysBack < 0.5 ? model.weeklyRate(metric) : nil)
                            .onTapGesture { chartMetric = metric }
                    }
                }
                if let lean = model.trendValue(.leanMass, at: shownDate), let height = model.profile.heightMeters {
                    FFMITile(ffmi: BodyComposition.normalizedFFMI(leanKilograms: lean, heightMeters: height))
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        let fat = model.trendValue(.fatPercent, at: shownDate)
        Section("Analysis") {
            if let fat {
                let band = FatBand.band(percent: fat, sex: model.profile.sex)
                LabeledContent("Body fat") {
                    Text(band.title)
                        .foregroundStyle(band.color)
                }
            } else {
                Text("No body fat readings yet. The figure estimates it from your BMI, age and sex, which can be off by about 4 points.")
                    .foregroundStyle(.secondary)
            }
            if let change = model.recentChange, daysBack < 0.5 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.title)
                        .font(.headline)
                    Text(change.detail)
                        .foregroundStyle(.secondary)
                }
            }
            if let visceral = model.trendValue(.visceralFat, at: shownDate) {
                LabeledContent("Visceral fat") {
                    Text(visceral <= 12 ? String(localized: "Healthy range") : String(localized: "High"))
                        .foregroundStyle(visceral <= 12 ? Theme.good : Theme.food)
                }
            }
        }
    }

    private var chartSection: some View {
        Section {
            Picker("Measurement", selection: $chartMetric) {
                ForEach(model.availableMetrics) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            if let points = model.trends[chartMetric], !points.isEmpty {
                MetricChart(points: points, metric: chartMetric)
                    .frame(height: 220)
            }
        } header: {
            Text("History")
        } footer: {
            Text("Dots are weigh-ins and the line is the trend. Hollow dots were far off and not confirmed by the next weigh-in, so they do not move the trend.")
        }
    }

    private var sourcesSection: some View {
        Section("Sources") {
            if model.hasAskedHealth {
                Label("Health app: weight, body fat and lean mass", systemImage: "heart.fill")
            } else {
                Button("Read from the Health app", systemImage: "heart.fill") {
                    Task { await model.requestHealthAccess() }
                }
            }
            Button {
                showingWithings = true
            } label: {
                HStack {
                    Label("Withings", systemImage: "scalemass.fill")
                    Spacer()
                    Text(model.withingsConnected ? String(localized: "Connected") : String(localized: "Not connected"))
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.withingsError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.food)
            }
        }
    }
}

// MARK: Pieces

private struct MetricTile: View {
    let metric: BodyMetric
    let value: Double
    let weeklyRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.format(value))
                    .font(Theme.number(30))
                Text(metric.unitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let weeklyRate, abs(weeklyRate) >= metric.rateDisplayThreshold {
                let improving = (weeklyRate < 0) == metric.lowerIsBetter
                Text("\(weeklyRate > 0 ? "+" : "")\(metric.format(weeklyRate)) \(metric.unitLabel)/week")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(improving ? Theme.good : Theme.food)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct FFMITile: View {
    let ffmi: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Muscularity (FFMI)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(ffmi.formatted(.number.precision(.fractionLength(1))))
                .font(Theme.number(30))
            Text("Lean mass for your height")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct MetricChart: View {
    let points: [TrendPoint]
    let metric: BodyMetric

    var body: some View {
        let values = points.flatMap { [$0.raw, $0.trend] }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.15, metric.noise)
        Chart {
            ForEach(points.filter { !$0.isOutlier }) { point in
                PointMark(x: .value("Date", point.date), y: .value("Reading", point.raw))
                    .symbolSize(18)
                    .foregroundStyle(Theme.accent.opacity(0.35))
            }
            ForEach(points.filter(\.isOutlier)) { point in
                PointMark(x: .value("Date", point.date), y: .value("Reading", point.raw))
                    .symbol(.circle.strokeBorder(lineWidth: 1.5))
                    .foregroundStyle(Theme.food)
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Trend", point.trend))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(Theme.accent)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
    }
}

// MARK: Labels

extension BodyMetric {
    var title: LocalizedStringResource {
        switch self {
        case .weight: "Weight"
        case .fatPercent: "Body fat"
        case .fatMass: "Fat mass"
        case .leanMass: "Lean mass"
        case .muscleMass: "Muscle mass"
        case .waterMass: "Body water"
        case .boneMass: "Bone mass"
        case .visceralFat: "Visceral fat"
        case .basalMetabolicRate: "Basal metabolism"
        case .metabolicAge: "Metabolic age"
        case .bmi: "BMI"
        }
    }

    var unitLabel: String {
        switch self {
        case .fatPercent: "%"
        case .basalMetabolicRate: "kcal"
        case .metabolicAge: String(localized: "yrs")
        case .visceralFat, .bmi: ""
        default: "kg"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .basalMetabolicRate, .metabolicAge:
            value.formatted(.number.precision(.fractionLength(0)))
        case .boneMass:
            value.formatted(.number.precision(.fractionLength(2)))
        default:
            value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// Weekly changes smaller than this are not shown.
    var rateDisplayThreshold: Double {
        switch self {
        case .basalMetabolicRate: 5
        case .metabolicAge: 0.3
        case .boneMass: 0.02
        default: 0.05
        }
    }
}

extension FatBand {
    var title: LocalizedStringResource {
        switch self {
        case .essential: "Very low"
        case .athletic: "Athletic"
        case .fit: "Fit"
        case .average: "Average"
        case .high: "High"
        }
    }

    var color: Color {
        switch self {
        case .essential: Theme.food
        case .athletic, .fit: Theme.good
        case .average: Theme.accent
        case .high: Theme.food
        }
    }
}

extension BodyChange {
    var title: LocalizedStringResource {
        switch self {
        case .recomposition: "Recomposition"
        case .cutting: "Losing fat"
        case .losingLean: "Losing lean mass"
        case .leanGain: "Building muscle"
        case .bulking: "Bulking"
        case .gainingFat: "Gaining fat"
        case .stable: "Stable"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .recomposition: "Over the last 4 weeks your fat is going down while your lean mass holds or grows."
        case .cutting: "Over the last 4 weeks you are losing fat and a little lean mass. Enough protein and lifting help keep the muscle."
        case .losingLean: "Over the last 4 weeks you are losing more lean mass than fat. Check protein, lifting and how fast you are losing weight."
        case .leanGain: "Over the last 4 weeks your lean mass is going up with little or no fat."
        case .bulking: "Over the last 4 weeks you are gaining lean mass and some fat."
        case .gainingFat: "Over the last 4 weeks you are gaining mostly fat."
        case .stable: "Over the last 4 weeks your fat and lean mass have barely changed."
        }
    }
}
