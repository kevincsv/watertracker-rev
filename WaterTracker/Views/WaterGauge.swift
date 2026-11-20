import Combine
import SwiftUI

/// The round "glass" on the Today screen. It fills with water as the day's
/// total approaches the goal.
struct WaterGauge: View {
    let progress: Double
    let amount: String
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var motion = LiquidMotion()
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// The water follows the phone (motion sensors) only while it is on
    /// screen, the app is active, and neither Reduce Motion nor Low Power Mode
    /// is on.
    private var followsMotion: Bool {
        isVisible && scenePhase == .active && !reduceMotion && !lowPower
    }

    var body: some View {
        // The wave only moves while the app is on screen, at a modest frame
        // rate, and not at all when Reduce Motion is on.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = Angle.degrees(reduceMotion ? 0 : (seconds * 60).truncatingRemainder(dividingBy: 360))
            let liquid = motion.physics

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                // A lighter wave behind the main one gives the water depth.
                Wave(phase: .radians(-1.3 * phase.radians + 2.1), level: min(progress, 1), tilt: liquid.tilt, slosh: liquid.slosh)
                    .fill(Color.accentColor.opacity(0.3))
                    .clipShape(Circle())
                    .animation(.easeInOut(duration: 0.8), value: progress)
                Wave(phase: phase, level: min(progress, 1), tilt: liquid.tilt, slosh: liquid.slosh)
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
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 4)

                VStack(spacing: 4) {
                    Text(amount)
                        .font(Theme.number(60))
                        .contentTransition(.numericText())
                    Text(caption)
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: followsMotion, initial: true) { _, follows in
            motion.setActive(follows)
        }
        .onChange(of: progress) { old, new in
            if new > old { motion.splash() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
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
