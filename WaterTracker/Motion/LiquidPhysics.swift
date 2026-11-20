import Foundation

/// How the screen is turned relative to the device, so that gravity can be
/// read in the coordinates the user actually sees (the iPad rotates its UI).
nonisolated enum ScreenTurn: Sendable {
    case portrait
    case upsideDown
    /// Home edge on the right: the device's top points left.
    case landscapeRight
    /// Home edge on the left: the device's top points right.
    case landscapeLeft
}

/// A tiny spring model of the water's surface. It is pure maths so it can be
/// tested without a device; `LiquidMotion` feeds it CoreMotion samples.
///
/// `tilt` is the angle of the surface on screen in radians: positive means the
/// right side of the water is higher. `slosh` (0...1) makes the waves taller
/// for a moment after a shake or a new drink, then fades.
nonisolated struct LiquidPhysics: Sendable, Equatable {
    var tilt: Double = 0
    var velocity: Double = 0
    var slosh: Double = 0

    /// The surface never leans more than this, so the glass always reads well.
    static let maxTilt = 0.7
    static let stiffness = 55.0
    static let damping = 5.5

    /// The surface angle that would be level with the floor, given gravity in
    /// device coordinates (CoreMotion's `gravity.x` / `gravity.y`, in g).
    static func targetTilt(gravityX: Double, gravityY: Double, turn: ScreenTurn = .portrait) -> Double {
        let (x, y): (Double, Double)
        switch turn {
        case .portrait: (x, y) = (gravityX, gravityY)
        case .upsideDown: (x, y) = (-gravityX, -gravityY)
        case .landscapeRight: (x, y) = (-gravityY, gravityX)
        case .landscapeLeft: (x, y) = (gravityY, -gravityX)
        }

        // Lying flat on a table there is no clear "down" on screen, and when
        // the screen faces the floor upside down the angle would flip around:
        // ease the surface back to level in both cases.
        let planar = (x * x + y * y).squareRoot()
        let flatWeight = min(1, max(0, (planar - 0.15) / 0.35))
        let uprightWeight = min(1, max(0, (0.3 - y) / 0.5))
        let weight = flatWeight * uprightWeight
        guard weight > 0 else { return 0 }

        let angle = atan2(x, -y) * weight
        return min(max(angle, -maxTilt), maxTilt)
    }

    /// Advances the spring by `dt` seconds.
    /// - Parameters:
    ///   - lateralAcceleration: sideways push from the user moving the phone,
    ///     in g, already in screen coordinates (positive = to the right).
    ///   - shake: overall user acceleration in g.
    mutating func step(target: Double, lateralAcceleration: Double, shake: Double, dt: Double) {
        let dt = min(max(dt, 0), 0.1)
        guard dt > 0 else { return }

        // Moving the phone right leaves the water behind on the left.
        let push = -lateralAcceleration * 14
        let acceleration = Self.stiffness * (target - tilt) - Self.damping * velocity + push
        velocity += acceleration * dt
        tilt = min(max(tilt + velocity * dt, -Self.maxTilt), Self.maxTilt)

        let excitement = min(1, max(abs(shake) * 1.2, abs(velocity) * 0.12))
        slosh = max(slosh * exp(-1.6 * dt), excitement)
    }

    /// A little splash, for when a drink is logged.
    mutating func splash() {
        slosh = 1
        velocity += 1.2
    }
}
