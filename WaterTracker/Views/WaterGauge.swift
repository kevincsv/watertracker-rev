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
    @State private var liquid = LiquidBox()
    @State private var isVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var splashes = 0

    /// The water follows the phone (motion sensors) only while it is on
    /// screen, the app is active, and neither Reduce Motion nor Low Power Mode
    /// is on.
    private var followsMotion: Bool {
        isVisible && scenePhase == .active && !reduceMotion && !lowPower
    }

    var body: some View {
        // The water only moves while the gauge is on screen and the app is
        // active, and not at all with Reduce Motion. Low Power Mode halves the
        // frame rate and turns the sensors off.
        TimelineView(.animation(
            minimumInterval: lowPower ? 1 / 30 : 1 / 60,
            paused: reduceMotion || scenePhase != .active || !isVisible
        )) { context in
            let frame = liquid.frame(
                at: context.date.timeIntervalSinceReferenceDate,
                fill: progress,
                input: motion.latest,
                animated: !reduceMotion
            )

            ZStack {
                Canvas { graphics, size in
                    WaterRenderer.draw(frame, in: &graphics, size: size)
                }
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
            .contentShape(Circle())
            .onTapGesture { location in
                guard !reduceMotion else { return }
                liquid.splash(at: location)
                splashes += 1
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { liquid.size = $0 }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: splashes)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: followsMotion, initial: true) { _, follows in
            motion.setActive(follows)
        }
        .onChange(of: progress) { old, new in
            // A new drink lands in the middle of the glass.
            if new > old, !reduceMotion {
                liquid.splash(at: CGPoint(x: liquid.size.width / 2, y: liquid.size.height / 2), strength: 1.3)
            }
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

/// Holds the water simulation between frames without making SwiftUI redraw
/// on every change (the timeline already redraws each frame).
final class LiquidBox {
    var simulation = LiquidSimulation()
    var size: CGSize = .zero

    func frame(at time: TimeInterval, fill: Double, input: MotionInput?, animated: Bool) -> WaterFrame {
        simulation.advance(to: time, targetFill: fill, input: input, animated: animated)
        return WaterFrame(simulation: simulation, time: animated ? time : 0)
    }

    func splash(at point: CGPoint, strength: Double = 1) {
        simulation.splash(at: point, in: size, strength: strength)
    }
}

#Preview {
    WaterGauge(progress: 0.52, amount: "1,250 ml", caption: "of 2,400 ml")
        .padding()
}
