import CoreMotion
import Observation
import UIKit

/// Reads the iPhone's motion sensors and turns them into a water surface that
/// stays level and sloshes as the phone moves.
///
/// Battery: the sensors only run while the gauge is on screen, the app is
/// active, Reduce Motion is off and Low Power Mode is off, at 30 updates a
/// second. Device motion needs no permission prompt and nothing leaves the
/// phone.
@Observable
final class LiquidMotion {
    private(set) var physics = LiquidPhysics()

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var lastTimestamp: TimeInterval?

    var isRunning: Bool { manager.isDeviceMotionActive }

    /// Starts or stops the sensors to match whether the water should move.
    func setActive(_ active: Bool) {
        if active { start() } else { stop() }
    }

    func splash() {
        guard isRunning else { return }
        physics.splash()
    }

    private func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        lastTimestamp = nil
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let sample = Sample(
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                timestamp: motion.timestamp
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
        lastTimestamp = nil
        physics = LiquidPhysics()
    }

    private func ingest(_ sample: Sample) {
        let dt = lastTimestamp.map { sample.timestamp - $0 } ?? 1 / 30
        lastTimestamp = sample.timestamp

        let turn = currentTurn()
        let target = LiquidPhysics.targetTilt(gravityX: sample.gravityX, gravityY: sample.gravityY, turn: turn)
        let lateral: Double
        switch turn {
        case .portrait: lateral = sample.accelerationX
        case .upsideDown: lateral = -sample.accelerationX
        case .landscapeRight: lateral = -sample.accelerationY
        case .landscapeLeft: lateral = sample.accelerationY
        }
        let shake = (sample.accelerationX * sample.accelerationX
            + sample.accelerationY * sample.accelerationY
            + sample.accelerationZ * sample.accelerationZ).squareRoot()

        var next = physics
        next.step(target: target, lateralAcceleration: lateral, shake: shake, dt: dt)
        physics = next
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
        let timestamp: TimeInterval
    }
}
