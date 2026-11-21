import CoreGraphics
import Foundation

/// The water in the gauge, frame by frame: a particle fluid pulled by the
/// phone's gravity and shaken by its movement, with as many particles as the
/// amount drunk. New water pours in from the top. Pure value type; the gauge
/// advances it once per frame.
nonisolated struct LiquidSimulation: Sendable {
    /// Particles in a completely full glass.
    static let fullCount = 1030
    /// Gravity, in glass radii per second squared, when the phone is upright.
    static let gravity = 16.0
    /// How much moving the phone pushes the water, relative to gravity.
    static let shakeGain = 1.5

    private(set) var fluid = ParticleFluid()
    /// The level being shown, 0...1.
    private(set) var fill: Double = 0
    /// True when the water is drawn flat and still (Reduce Motion).
    private(set) var isStill = true
    /// Which way is down on screen (y points down the screen), eased so the
    /// shading follows the phone smoothly.
    private(set) var downX = 0.0
    private(set) var downY = 1.0
    /// True while the water has come to rest and nothing is moving it.
    private(set) var isAsleep = false

    private var gravityX = 0.0
    private var gravityY = 1.0
    private var lastTime: TimeInterval?
    private var isSeeded = false
    private var pourCredit = 0.0
    private var calmTime = 0.0
    private var restingPullX = 0.0
    private var restingPullY = 0.0

    /// How many particles the level `fill` needs.
    static func particleCount(fill: Double) -> Int {
        Int((min(max(fill, 0), 1) * Double(fullCount)).rounded())
    }

    /// Where the flat surface would sit, from the centre along "down",
    /// radius 1.
    var surfaceOffset: Double { LiquidGeometry.surfaceOffset(fill: fill) }

    /// - Parameters:
    ///   - time: the frame's time, in seconds.
    ///   - targetFill: the real level, 0...1.
    ///   - input: the motion sensors, or nil when they are off (gravity
    ///     then points down the screen).
    ///   - animated: false with Reduce Motion: the water is drawn still.
    mutating func advance(to time: TimeInterval, targetFill: Double, input: MotionInput?, animated: Bool) {
        let dt = lastTime.map { min(max(time - $0, 0), 1.0 / 30) } ?? 0
        lastTime = time
        fill = min(max(targetFill, 0), 1)

        guard animated else {
            isStill = true
            isSeeded = false
            isAsleep = false
            fluid.removeAll()
            downX = 0
            downY = 1
            return
        }
        isStill = false

        let target = Self.particleCount(fill: fill)
        if !isSeeded {
            fluid.seed(count: target)
            isSeeded = true
            calmTime = 0
            isAsleep = false
        }
        guard dt > 0 else { return }

        // Which way the water is pulled: gravity as the screen sees it, plus
        // the push from moving the phone (water lags behind the glass).
        var pullX = 0.0
        var pullY = 1.0
        if let input {
            let x = input.gravityX
            let y = -input.gravityY
            let strength = (x * x + y * y).squareRoot()
            if strength > 0.25 {
                gravityX = x
                gravityY = y
            } else {
                // Lying flat there is no clear "down": keep the last one,
                // gently, so the water stays where it was.
                let last = max((gravityX * gravityX + gravityY * gravityY).squareRoot(), 1e-6)
                gravityX *= 0.25 / last
                gravityY *= 0.25 / last
            }
            pullX = gravityX - input.accelerationX * Self.shakeGain
            pullY = gravityY + input.accelerationY * Self.shakeGain
            let pull = (pullX * pullX + pullY * pullY).squareRoot()
            if pull > 3 {
                pullX *= 3 / pull
                pullY *= 3 / pull
            }
        } else {
            gravityX = 0
            gravityY = 1
        }

        let gravityLength = max((gravityX * gravityX + gravityY * gravityY).squareRoot(), 1e-6)
        let unitX = gravityX / gravityLength
        let unitY = gravityY / gravityLength
        let blend = 1 - exp(-10 * dt)
        downX += (unitX - downX) * blend
        downY += (unitY - downY) * blend

        // Match the amount of water to the amount drunk.
        if fluid.count < target {
            let missing = Double(target - fluid.count)
            pourCredit += max(260, missing * 1.5) * dt
            while pourCredit >= 1, fluid.count < target {
                pourCredit -= 1
                fluid.pour(downX: unitX, downY: unitY)
            }
            wake()
        } else {
            pourCredit = 0
            if fluid.count > target {
                for _ in 0..<min(fluid.count - target, 8) {
                    fluid.removeHighest(downX: unitX, downY: unitY)
                }
                wake()
            }
        }

        // Still water that nothing is moving does not need simulating.
        if isAsleep, abs(pullX - restingPullX) + abs(pullY - restingPullY) > 0.03 {
            wake()
        }
        guard !isAsleep else { return }

        let steps = min(4, max(1, Int((dt * 120 - 0.01).rounded(.up))))
        let stepTime = dt / Double(steps)
        for _ in 0..<steps {
            fluid.step(dt: stepTime, pullX: pullX * Self.gravity, pullY: pullY * Self.gravity)
        }

        if fluid.averageSpeed < 0.08, fluid.count == target {
            calmTime += dt
            if calmTime > 1.5 {
                isAsleep = true
                restingPullX = pullX
                restingPullY = pullY
            }
        } else {
            calmTime = 0
        }
    }

    private mutating func wake() {
        isAsleep = false
        calmTime = 0
    }

    /// A splash where the user touched the glass, if there is water there.
    /// `point` is in the gauge's own coordinates and `size` is the gauge's
    /// size. Returns whether the tap hit water.
    @discardableResult
    mutating func splash(at point: CGPoint, in size: CGSize, strength: Double = 1) -> Bool {
        let radius = min(size.width, size.height) / 2
        guard radius > 0, !isStill else { return false }
        let x = Double((point.x - size.width / 2) / radius)
        let y = Double((point.y - size.height / 2) / radius)
        guard fluid.particles(nearX: x, y: y, radius: 0.09) >= 2 else { return false }

        let length = max((gravityX * gravityX + gravityY * gravityY).squareRoot(), 1e-6)
        fluid.splash(atX: x, y: y, upX: -gravityX / length, upY: -gravityY / length, strength: strength)
        wake()
        return true
    }
}
