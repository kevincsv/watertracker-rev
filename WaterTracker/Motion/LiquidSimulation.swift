import CoreGraphics
import Foundation

/// Everything the water in the gauge does, frame by frame: which way it
/// leans, its waves, drops and bubbles, and the level easing towards the
/// amount drunk. Pure value type; the gauge advances it once per frame.
nonisolated struct LiquidSimulation: Sendable {
    var tilt = LiquidTilt()
    var surface = WaterSurface()
    /// The level being shown (0...1), which eases towards the real one.
    var fill: Double = 0
    private var lastTime: TimeInterval?

    /// Where the flat surface sits, from the centre along "down", radius 1.
    var surfaceOffset: Double { LiquidGeometry.surfaceOffset(fill: fill) }

    /// - Parameters:
    ///   - time: the frame's time, in seconds.
    ///   - targetFill: the real level, 0...1.
    ///   - input: the motion sensors, or nil when they are off (the water
    ///     then settles upright).
    ///   - animated: false with Reduce Motion: the water is drawn still.
    mutating func advance(to time: TimeInterval, targetFill: Double, input: MotionInput?, animated: Bool) {
        let targetFill = min(max(targetFill, 0), 1)
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time

        guard animated else {
            fill = targetFill
            tilt = LiquidTilt()
            surface = WaterSurface()
            return
        }
        guard dt > 0 else { return }

        fill += (targetFill - fill) * (1 - exp(-3 * dt))

        let previousVelocity = tilt.velocity
        let target: Double? = if let input {
            LiquidTilt.targetAngle(gravityX: input.gravityX, gravityY: input.gravityY)
        } else {
            0
        }
        let lateral = input.map { $0.accelerationX * cos(tilt.angle) + $0.accelerationY * sin(tilt.angle) } ?? 0
        tilt.step(target: target, lateralAcceleration: lateral, dt: dt)

        // When the glass turns faster or slower, the water piles up on one
        // side and sloshes back.
        surface.slosh((previousVelocity - tilt.velocity) * 0.3)
        if let input, input.shake > 0.12 {
            surface.stir(amount: min(input.shake, 2) * 2)
        }
        surface.stir(amount: 0.05)
        surface.step(dt: dt, surfaceY: surfaceOffset)
    }

    /// A splash where the user touched the glass. `point` is in the gauge's
    /// own coordinates and `size` is the gauge's size.
    mutating func splash(at point: CGPoint, in size: CGSize, strength: Double = 1) {
        let radius = min(size.width, size.height) / 2
        guard radius > 0, fill > 0 else { return }
        let x = Double((point.x - size.width / 2) / radius)
        let y = Double((point.y - size.height / 2) / radius)
        // Into the water's own frame, where "down" is +y.
        let glassX = x * cos(tilt.angle) - y * sin(tilt.angle)
        surface.splash(at: min(max(glassX, -0.95), 0.95), surfaceY: surfaceOffset, strength: strength)
    }
}
