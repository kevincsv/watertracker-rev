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

    /// Turns a vector from device coordinates (x right, y up, as CoreMotion
    /// reports it) into screen coordinates (same convention).
    func screenVector(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .portrait: return (x, y)
        case .upsideDown: return (-x, -y)
        case .landscapeRight: return (-y, x)
        case .landscapeLeft: return (y, -x)
        }
    }
}

/// Which way "down" is for the water, as an angle on screen, and a spring
/// that makes it follow the phone like a real liquid would: it lags, slides
/// round the glass and overshoots a little.
///
/// `angle` is 0 when down is the bottom of the screen, positive when down
/// leans towards the right edge, and ±π when the phone is upside down (the
/// water then sits at the top of the screen).
nonisolated struct LiquidTilt: Sendable, Equatable {
    var angle: Double = 0
    var velocity: Double = 0

    static let stiffness = 38.0
    static let damping = 7.0
    static let maxVelocity = 14.0

    /// The direction of gravity on screen, or nil when the phone lies flat
    /// and there is no clear "down" (the water then stays where it was).
    static func targetAngle(gravityX: Double, gravityY: Double, turn: ScreenTurn = .portrait) -> Double? {
        let (x, y) = turn.screenVector(x: gravityX, y: gravityY)
        guard (x * x + y * y).squareRoot() > 0.25 else { return nil }
        return atan2(x, -y)
    }

    /// The shortest signed turn from `from` to `to`, in -π...π.
    static func shortestTurn(from: Double, to: Double) -> Double {
        var difference = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if difference > .pi { difference -= 2 * .pi }
        if difference < -.pi { difference += 2 * .pi }
        return difference
    }

    /// Advances the spring by `dt` seconds.
    /// - Parameters:
    ///   - target: where down is now, or nil to hold.
    ///   - lateralAcceleration: sideways push from moving the phone, in g,
    ///     across the water (positive = towards the water's right).
    mutating func step(target: Double?, lateralAcceleration: Double, dt: Double) {
        let dt = min(max(dt, 0), 0.1)
        guard dt > 0 else { return }

        let pull = target.map { Self.stiffness * Self.shortestTurn(from: angle, to: $0) } ?? 0
        // Moving the phone right leaves the water behind on the left, which
        // looks like down leaning left for a moment.
        let push = -lateralAcceleration * 16
        velocity += (pull - Self.damping * velocity + push) * dt
        velocity = min(max(velocity, -Self.maxVelocity), Self.maxVelocity)
        angle = Self.shortestTurn(from: 0, to: angle + velocity * dt)
    }
}

/// Geometry of water in a round glass of radius 1.
nonisolated enum LiquidGeometry {
    /// Where the flat surface sits, measured from the centre along "down",
    /// so that the water below it fills `fill` (0...1) of the circle. The same
    /// amount of water then shows at any angle, as in a real glass.
    /// 1 is empty (surface at the very bottom), -1 is full.
    static func surfaceOffset(fill: Double) -> Double {
        let fill = min(max(fill, 0), 1)
        if fill <= 0 { return 1 }
        if fill >= 1 { return -1 }
        var low = -1.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if filledFraction(surfaceOffset: mid) > fill { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// The share of the circle below a surface at `surfaceOffset`.
    static func filledFraction(surfaceOffset s: Double) -> Double {
        let s = min(max(s, -1), 1)
        return (acos(s) - s * (1 - s * s).squareRoot()) / .pi
    }
}
