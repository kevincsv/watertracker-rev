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
