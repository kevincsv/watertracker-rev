import Foundation

/// The moving surface of the water, simulated as a row of small columns that
/// pull on their neighbours (a 1D wave equation), plus the drops thrown up by
/// a splash and a few bubbles. Units are the glass radius: x runs from -1 to
/// 1 across the glass and y points "down", so a negative height is a crest.
///
/// Pure value type so it can be tested without a screen.
nonisolated struct WaterSurface: Sendable {
    nonisolated struct Drop: Sendable, Equatable {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var radius: Double
    }

    nonisolated struct Bubble: Sendable, Equatable {
        var x: Double
        /// Depth below the surface.
        var depth: Double
        var speed: Double
        var radius: Double
        var wobble: Double
    }

    static let columnCount = 48
    static let waveSpeed = 1.5
    static let damping = 1.4
    static let gravity = 4.5
    static let maxHeight = 0.28
    static let maxDrops = 48
    static let maxBubbles = 24

    private(set) var heights = [Double](repeating: 0, count: columnCount)
    private(set) var velocities = [Double](repeating: 0, count: columnCount)
    private(set) var drops: [Drop] = []
    private(set) var bubbles: [Bubble] = []
    private var random = SplitMix(seed: 0x5EED)

    static func columnX(_ index: Int) -> Double {
        -1 + 2 * Double(index) / Double(columnCount - 1)
    }

    /// Height of the surface at `x`, interpolated between columns.
    func height(at x: Double) -> Double {
        let position = (min(max(x, -1), 1) + 1) / 2 * Double(Self.columnCount - 1)
        let index = min(Int(position), Self.columnCount - 2)
        let t = position - Double(index)
        return heights[index] * (1 - t) + heights[index + 1] * t
    }

    /// Total motion left in the water; near 0 means it is still.
    var energy: Double {
        zip(heights, velocities).reduce(0) { $0 + $1.0 * $1.0 * 20 + $1.1 * $1.1 } / Double(Self.columnCount)
    }

    var isCalm: Bool { energy < 1e-5 && drops.isEmpty && bubbles.isEmpty }

    /// A push down into the water at `x`, spreading out as rings.
    mutating func disturb(at x: Double, strength: Double, width: Double = 0.14) {
        for index in heights.indices {
            let distance = (Self.columnX(index) - x) / width
            velocities[index] += strength * exp(-distance * distance)
        }
    }

    /// Tilts the whole surface for a moment, as when the glass is jolted
    /// sideways (positive raises the right side).
    mutating func slosh(_ amount: Double) {
        for index in heights.indices {
            velocities[index] -= amount * Self.columnX(index)
        }
    }

    /// A splash at `x` on a surface sitting at `surfaceY`: a dip, drops
    /// flying up and some bubbles. `strength` around 1 is a finger tap.
    mutating func splash(at x: Double, surfaceY: Double, strength: Double = 1) {
        let strength = min(max(strength, 0), 2)
        disturb(at: x, strength: 2.6 * strength)

        let dropCount = Int(6 + 6 * strength)
        for _ in 0..<dropCount where drops.count < Self.maxDrops {
            let spread = random.next(in: -0.08...0.08)
            drops.append(Drop(
                x: x + spread,
                y: surfaceY + height(at: x) - 0.01,
                vx: spread * 6 + random.next(in: -0.35...0.35),
                vy: -strength * random.next(in: 1.1...2.3),
                radius: random.next(in: 0.012...0.032)
            ))
        }

        let bubbleCount = Int(3 + 4 * strength)
        for _ in 0..<bubbleCount where bubbles.count < Self.maxBubbles {
            bubbles.append(Bubble(
                x: x + random.next(in: -0.15...0.15),
                depth: random.next(in: 0.08...0.4),
                speed: random.next(in: 0.25...0.6),
                radius: random.next(in: 0.01...0.028),
                wobble: random.next(in: 0...(2 * .pi))
            ))
        }
    }

    /// Small, constant stirring so the water is never perfectly dead.
    mutating func stir(amount: Double) {
        guard amount > 0 else { return }
        let index = Int(random.next(in: 0...Double(Self.columnCount - 1)))
        velocities[index] += random.next(in: -amount...amount)
    }

    /// Advances everything by `dt` seconds. `surfaceY` is where the flat
    /// surface sits, used to land drops back in the water.
    mutating func step(dt: Double, surfaceY: Double) {
        let dt = min(max(dt, 0), 0.1)
        guard dt > 0 else { return }

        // Small sub-steps keep the wave equation stable at any frame rate.
        let spacing = 2 / Double(Self.columnCount - 1)
        let stiffness = Self.waveSpeed * Self.waveSpeed / (spacing * spacing)
        let substeps = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
        let h = dt / Double(substeps)
        let last = Self.columnCount - 1

        for _ in 0..<substeps {
            for index in heights.indices {
                let left = heights[max(index - 1, 0)]
                let right = heights[min(index + 1, last)]
                let laplacian = left + right - 2 * heights[index]
                velocities[index] += (stiffness * laplacian - Self.damping * velocities[index] - 2 * heights[index]) * h
            }
            for index in heights.indices {
                heights[index] = min(max(heights[index] + velocities[index] * h, -Self.maxHeight), Self.maxHeight)
            }
        }

        // Water is not created or lost: keep the average height at zero so
        // the level always matches the amount drunk.
        let mean = heights.reduce(0, +) / Double(Self.columnCount)
        for index in heights.indices { heights[index] -= mean }

        var flying: [Drop] = []
        var landed: [Drop] = []
        for var drop in drops {
            drop.vy += Self.gravity * dt
            drop.x += drop.vx * dt
            drop.y += drop.vy * dt
            if drop.vy > 0, drop.y >= surfaceY + height(at: drop.x) {
                landed.append(drop)
            } else if drop.x * drop.x + drop.y * drop.y < 1.6 {
                flying.append(drop)
            }
        }
        drops = flying
        for drop in landed {
            disturb(at: drop.x, strength: drop.radius * 6, width: 0.06)
        }

        bubbles = bubbles.compactMap { bubble in
            var bubble = bubble
            bubble.depth -= bubble.speed * dt
            bubble.wobble += dt * 9
            bubble.x += sin(bubble.wobble) * 0.08 * dt
            return bubble.depth > 0 ? bubble : nil
        }
    }
}

/// A tiny deterministic random generator, so the simulation behaves the same
/// way in tests.
nonisolated struct SplitMix: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(nextUInt64() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
