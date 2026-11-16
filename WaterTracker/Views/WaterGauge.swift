import SwiftUI

/// The round "glass" on the Today screen. It fills with water as the day's
/// total approaches the goal.
struct WaterGauge: View {
    let progress: Double
    let amount: String
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The wave only moves while the app is on screen, at a modest frame
        // rate, and not at all when Reduce Motion is on.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = Angle.degrees(reduceMotion ? 0 : (seconds * 60).truncatingRemainder(dividingBy: 360))

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Wave(phase: phase, level: min(progress, 1))
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Circle())
                    .animation(.easeInOut(duration: 0.8), value: progress)
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)

                VStack(spacing: 4) {
                    Text(amount)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text(caption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Water today"))
        .accessibilityValue(Text("\(amount), \(caption)"))
    }
}

#Preview {
    WaterGauge(progress: 0.52, amount: "1,250 ml", caption: "of 2,400 ml")
        .padding()
}
