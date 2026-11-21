import CoreMotion
import UIKit

/// What the motion sensors say right now, already turned into the
/// coordinates of the screen the user sees.
nonisolated struct MotionInput: Sendable, Equatable {
    /// Gravity on screen (x right, y up), in g.
    var gravityX: Double
    var gravityY: Double
    /// Acceleration the user gives the phone, on screen, in g.
    var accelerationX: Double
    var accelerationY: Double
    /// Overall user acceleration (all three axes), in g.
    var shake: Double
}

/// Reads the iPhone's motion sensors for the water in the gauge.
///
/// Battery: the sensors only run while the gauge is on screen, the app is
/// active, Reduce Motion is off and Low Power Mode is off. Device motion
/// needs no permission prompt and nothing leaves the phone.
final class LiquidMotion {
    private(set) var latest: MotionInput?

    private let manager = CMMotionManager()

    var isRunning: Bool { manager.isDeviceMotionActive }

    /// Starts or stops the sensors to match whether the water should move.
    func setActive(_ active: Bool) {
        if active { start() } else { stop() }
    }

    private func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let sample = Sample(
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z
            )
            MainActor.assumeIsolated {
                self?.ingest(sample)
            }
        }
    }

    private func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        latest = nil
    }

    private func ingest(_ sample: Sample) {
        let turn = currentTurn()
        let gravity = turn.screenVector(x: sample.gravityX, y: sample.gravityY)
        let acceleration = turn.screenVector(x: sample.accelerationX, y: sample.accelerationY)
        let shake = (sample.accelerationX * sample.accelerationX
            + sample.accelerationY * sample.accelerationY
            + sample.accelerationZ * sample.accelerationZ).squareRoot()
        latest = MotionInput(
            gravityX: gravity.x,
            gravityY: gravity.y,
            accelerationX: acceleration.x,
            accelerationY: acceleration.y,
            shake: shake
        )
    }

    private func currentTurn() -> ScreenTurn {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        switch scene?.effectiveGeometry.interfaceOrientation {
        case .portraitUpsideDown: return .upsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }

    private nonisolated struct Sample: Sendable {
        let gravityX: Double
        let gravityY: Double
        let accelerationX: Double
        let accelerationY: Double
        let accelerationZ: Double
    }
}
