import Foundation

/// Water as a few hundred particles in a round glass of radius 1 (y points
/// down the screen). Each particle pushes its neighbours apart until the
/// water is evenly dense, which is what makes it pour, slosh, splash into
/// drops and settle flat like a real liquid ("double density relaxation",
/// Clavet et al. 2005).
///
/// Pure value type so it can be tested without a screen.
nonisolated struct ParticleFluid: Sendable {
    /// How far a particle feels its neighbours.
    static let reach = 0.17
    /// Particles stay inside this radius, so the drawn water meets the glass.
    static let wall = 0.965
    static let restDensity = 4.0
    static let stiffness = 60.0
    static let nearStiffness = 80.0
    static let maxSpeed = 9.0
    /// Water near the glass is slowed down, more the faster it runs, so it
    /// falls across the glass instead of racing round its edge.
    static let wallBand = 0.14
    static let wallDrag = 2.0
    static let wallSpeedDrag = 8.0
    /// How strongly neighbours even out their speeds. Strong in calm water
    /// (so it comes to rest), weak in fast water (so splashes stay lively).
    static let smoothing = 0.4
    static let smoothingFloor = 0.15
    static let smoothingFade = 0.5
    /// Distance between particles when the glass is first filled.
    static let seedSpacing = 0.057

    private(set) var x: [Double] = []
    private(set) var y: [Double] = []
    private(set) var vx: [Double] = []
    private(set) var vy: [Double] = []
    /// Average speed after the last step; near 0 means the water is still.
    private(set) var averageSpeed = 0.0

    private var previousX: [Double] = []
    private var previousY: [Double] = []
    private var pushX: [Double] = []
    private var pushY: [Double] = []
    private var cellOf: [Int] = []
    private var cellStart: [Int] = []
    private var cellItems: [Int] = []
    private var nearIndex = [Int](repeating: 0, count: ParticleFluid.maxNeighbours)
    private var nearCloseness = [Double](repeating: 0, count: ParticleFluid.maxNeighbours)
    private var nearX = [Double](repeating: 0, count: ParticleFluid.maxNeighbours)
    private var nearY = [Double](repeating: 0, count: ParticleFluid.maxNeighbours)
    private var random = SplitMix(seed: 0x5EED)

    private static let maxNeighbours = 64
    private static let gridSize = Int((2.2 / reach).rounded(.up)) + 1

    var count: Int { x.count }

    // MARK: Adding and removing water

    mutating func add(x newX: Double, y newY: Double, vx newVX: Double = 0, vy newVY: Double = 0) {
        x.append(newX)
        y.append(newY)
        vx.append(newVX)
        vy.append(newVY)
    }

    mutating func removeAll() {
        x.removeAll(keepingCapacity: true)
        y.removeAll(keepingCapacity: true)
        vx.removeAll(keepingCapacity: true)
        vy.removeAll(keepingCapacity: true)
        averageSpeed = 0
    }

    /// Replaces the water with `count` particles already lying at the bottom
    /// of the glass, so it does not have to fall in first.
    mutating func seed(count target: Int) {
        removeAll()
        guard target > 0 else { return }
        let spacing = Self.seedSpacing
        let radius = Self.wall - 0.01
        var rowY = radius
        var row = 0
        while rowY > -radius, count < target {
            let half = max(radius * radius - rowY * rowY, 0).squareRoot()
            var columnX = -half + (row % 2 == 0 ? 0 : spacing / 2)
            while columnX <= half, count < target {
                add(x: columnX, y: rowY)
                columnX += spacing
            }
            rowY -= spacing * 0.866
            row += 1
        }
    }

    /// Pours one particle in from the top of the glass. (`downX`, `downY`)
    /// is the unit direction of gravity.
    mutating func pour(downX: Double, downY: Double) {
        let across = random.next(in: -0.07...0.07)
        let along = -0.72 + random.next(in: -0.05...0.05)
        add(
            x: downX * along - downY * across,
            y: downY * along + downX * across,
            vx: downX * 3,
            vy: downY * 3
        )
    }

    /// Takes away the particle that sits highest, so the level drops from
    /// the surface.
    mutating func removeHighest(downX: Double, downY: Double) {
        guard count > 0 else { return }
        var highest = 0
        var lowestDepth = Double.infinity
        for index in 0..<count {
            let depth = x[index] * downX + y[index] * downY
            if depth < lowestDepth {
                lowestDepth = depth
                highest = index
            }
        }
        x.swapAt(highest, count - 1)
        y.swapAt(highest, count - 1)
        vx.swapAt(highest, count - 1)
        vy.swapAt(highest, count - 1)
        x.removeLast()
        y.removeLast()
        vx.removeLast()
        vy.removeLast()
    }

    // MARK: Touch

    /// How many particles lie within `radius` of a point: is there water there?
    func particles(nearX pointX: Double, y pointY: Double, radius: Double) -> Int {
        var found = 0
        for index in 0..<count {
            let dx = x[index] - pointX
            let dy = y[index] - pointY
            if dx * dx + dy * dy < radius * radius { found += 1 }
        }
        return found
    }

    /// Throws the water around a point outwards and up, as a finger tap
    /// would. (`upX`, `upY`) is the unit direction away from gravity.
    mutating func splash(atX pointX: Double, y pointY: Double, upX: Double, upY: Double, strength: Double = 1) {
        let radius = 0.3
        let power = 2.6 * min(max(strength, 0), 2)
        for index in 0..<count {
            let dx = x[index] - pointX
            let dy = y[index] - pointY
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance < radius else { continue }
            let weight = power * (1 - distance / radius)
            let safe = max(distance, 1e-3)
            let lift = 2.6 * random.next(in: 0.5...1.5)
            vx[index] += weight * (1.6 * dx / safe + lift * upX)
            vy[index] += weight * (1.6 * dy / safe + lift * upY)
        }
    }

    // MARK: Physics

    /// Advances the water by `dt` seconds under the given pull (gravity plus
    /// whatever shaking the phone adds), in glass radii per second squared.
    mutating func step(dt: Double, pullX: Double, pullY: Double) {
        let total = count
        guard total > 0, dt > 0 else { return }
        resizeScratch(total)

        for index in 0..<total {
            var speedX = vx[index] + pullX * dt
            var speedY = vy[index] + pullY * dt
            let speed = (speedX * speedX + speedY * speedY).squareRoot()
            if speed > Self.maxSpeed {
                speedX *= Self.maxSpeed / speed
                speedY *= Self.maxSpeed / speed
            }
            vx[index] = speedX
            vy[index] = speedY
            previousX[index] = x[index]
            previousY[index] = y[index]
            x[index] += speedX * dt
            y[index] += speedY * dt
        }

        buildGrid()
        relax(dt: dt)
        collide(dt: dt)
        smooth()
    }

    private mutating func resizeScratch(_ total: Int) {
        guard previousX.count != total else { return }
        previousX = [Double](repeating: 0, count: total)
        previousY = [Double](repeating: 0, count: total)
        pushX = [Double](repeating: 0, count: total)
        pushY = [Double](repeating: 0, count: total)
        cellOf = [Int](repeating: 0, count: total)
        cellItems = [Int](repeating: 0, count: total)
    }

    /// Sorts the particles into a grid of cells as wide as their reach, so
    /// each one only has to look at the cells around it.
    private mutating func buildGrid() {
        let size = Self.gridSize
        let cells = size * size
        let total = count
        if cellStart.count != cells + 1 {
            cellStart = [Int](repeating: 0, count: cells + 1)
        } else {
            for cell in 0...cells { cellStart[cell] = 0 }
        }
        for index in 0..<total {
            let column = min(max(Int((x[index] + 1.1) / Self.reach), 0), size - 1)
            let row = min(max(Int((y[index] + 1.1) / Self.reach), 0), size - 1)
            let cell = row * size + column
            cellOf[index] = cell
            cellStart[cell + 1] += 1
        }
        for cell in 0..<cells {
            cellStart[cell + 1] += cellStart[cell]
        }
        // Fill each cell from its end backwards, which leaves `cellStart`
        // pointing at the first item of every cell.
        for index in 0..<total {
            let cell = cellOf[index]
            cellStart[cell + 1] -= 1
            cellItems[cellStart[cell + 1]] = index
        }
        // Undo the shift: cellStart[cell + 1] now holds the start of `cell`.
        for cell in 0..<cells {
            cellStart[cell] = cellStart[cell + 1]
        }
        cellStart[cells] = total
    }

    /// Collects the neighbours of a particle into the `near…` buffers:
    /// who they are, how close (1 touching, 0 at the edge of reach) and in
    /// which direction. Returns how many there are.
    private mutating func gatherNeighbours(of index: Int) -> Int {
        let size = Self.gridSize
        let reach = Self.reach
        let cell = cellOf[index]
        let column = cell % size
        let row = cell / size
        let ownX = x[index]
        let ownY = y[index]
        var found = 0
        for nearRow in max(row - 1, 0)...min(row + 1, size - 1) {
            for nearColumn in max(column - 1, 0)...min(column + 1, size - 1) {
                let nearCell = nearRow * size + nearColumn
                var slot = cellStart[nearCell]
                let end = cellStart[nearCell + 1]
                while slot < end {
                    let other = cellItems[slot]
                    slot += 1
                    guard other != index else { continue }
                    let dx = x[other] - ownX
                    let dy = y[other] - ownY
                    let squared = dx * dx + dy * dy
                    guard squared < reach * reach, squared > 1e-12, found < Self.maxNeighbours else { continue }
                    let distance = squared.squareRoot()
                    nearIndex[found] = other
                    nearCloseness[found] = 1 - distance / reach
                    nearX[found] = dx / distance
                    nearY[found] = dy / distance
                    found += 1
                }
            }
        }
        return found
    }

    /// Pushes crowded particles apart and pulls sparse ones together.
    private mutating func relax(dt: Double) {
        let scale = dt * dt * 0.5
        for index in 0..<count {
            let found = gatherNeighbours(of: index)
            guard found > 0 else { continue }
            var density = 0.0
            var nearDensity = 0.0
            for slot in 0..<found {
                let closeness = nearCloseness[slot]
                density += closeness * closeness
                nearDensity += closeness * closeness * closeness
            }
            let pressure = Self.stiffness * (density - Self.restDensity)
            let nearPressure = Self.nearStiffness * nearDensity
            var ownX = 0.0
            var ownY = 0.0
            for slot in 0..<found {
                let closeness = nearCloseness[slot]
                let move = scale * (pressure * closeness + nearPressure * closeness * closeness)
                let other = nearIndex[slot]
                x[other] += move * nearX[slot]
                y[other] += move * nearY[slot]
                ownX -= move * nearX[slot]
                ownY -= move * nearY[slot]
            }
            x[index] += ownX
            y[index] += ownY
        }
    }

    /// Keeps the water inside the glass and works out each particle's speed
    /// from how far it actually moved.
    private mutating func collide(dt: Double) {
        let wall = Self.wall
        for index in 0..<count {
            var distance = (x[index] * x[index] + y[index] * y[index]).squareRoot()
            if distance > wall {
                x[index] *= wall / distance
                y[index] *= wall / distance
                distance = wall
            }
            var speedX = (x[index] - previousX[index]) / dt
            var speedY = (y[index] - previousY[index]) / dt
            let nearness = (distance - (wall - Self.wallBand)) / Self.wallBand
            if nearness > 0 {
                let speed = (speedX * speedX + speedY * speedY).squareRoot()
                let keep = 1 / (1 + nearness * (Self.wallDrag + Self.wallSpeedDrag * speed) * dt)
                speedX *= keep
                speedY *= keep
            }
            vx[index] = speedX
            vy[index] = speedY
        }
    }

    /// Evens out the speeds of neighbouring particles, which is what lets
    /// the water come to rest instead of trembling forever.
    private mutating func smooth() {
        let total = count
        for index in 0..<total {
            let found = gatherNeighbours(of: index)
            var sumX = 0.0
            var sumY = 0.0
            var weight = 0.0
            for slot in 0..<found {
                let other = nearIndex[slot]
                let closeness = nearCloseness[slot]
                sumX += (vx[other] - vx[index]) * closeness
                sumY += (vy[other] - vy[index]) * closeness
                weight += closeness
            }
            let squaredSpeed = vx[index] * vx[index] + vy[index] * vy[index]
            let calm = max(Self.smoothingFloor, 1 / (1 + Self.smoothingFade * squaredSpeed))
            let amount = Self.smoothing * calm / max(weight, 1)
            pushX[index] = amount * sumX
            pushY[index] = amount * sumY
        }
        var speedSum = 0.0
        for index in 0..<total {
            vx[index] += pushX[index]
            vy[index] += pushY[index]
            speedSum += (vx[index] * vx[index] + vy[index] * vy[index]).squareRoot()
        }
        averageSpeed = speedSum / Double(total)
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
