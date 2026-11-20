import Foundation
import simd

/// Triangles for one part of the figure.
nonisolated struct MeshData: Sendable, Equatable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}

/// Builds a smooth mannequin from a `BodyShape`, in meters, standing on y = 0
/// and facing +z.
///
/// Every part is a "loft": a chain of oval cross-sections joined into a tube
/// and capped at both ends. The sections follow average adult proportions as
/// fractions of height; fat widens and deepens the belly (and hips and thighs
/// for women, who store more fat there), muscle widens the shoulders, chest,
/// arms and legs. Sections are blended with Catmull-Rom curves so the
/// silhouette has no corners.
nonisolated enum BodyMesh {
    enum Part: String, CaseIterable, Sendable {
        case torso, head, arms, legs
    }

    /// One cross-section: centre, the two directions of its radii, and the
    /// radii along each.
    struct Section {
        var center: SIMD3<Float>
        var rx: Float
        var rz: Float
        var u: SIMD3<Float> = [1, 0, 0]
        var v: SIMD3<Float> = [0, 0, 1]
    }

    static let segments = 28

    static func build(_ shape: BodyShape) -> [Part: MeshData] {
        let h = Float(shape.heightMeters)
        let f = shape.fat
        let m = shape.muscle
        let female = shape.sex == .female
        let fatPos = max(f, 0)

        func w(_ fraction: Float) -> Float { fraction * h }

        // Torso half-widths and half-depths.
        let shoulder = w(female ? 0.098 : 0.112) * (1 + 0.07 * m + 0.03 * fatPos)
        let chest = w(female ? 0.086 : 0.094) * (1 + 0.05 * m + 0.07 * f)
        let waist = w(female ? 0.070 : 0.079) * (1 + 0.02 * m + (female ? 0.12 : 0.17) * f)
        let hip = w(female ? 0.104 : 0.092) * (1 + (female ? 0.13 : 0.07) * f)
        let chestDepth = w(female ? 0.066 : 0.068) * (1 + 0.07 * m + 0.07 * f)
        let bellyDepth = w(female ? 0.058 : 0.060) * (1 + (female ? 0.18 : 0.27) * f)
        let hipDepth = w(female ? 0.068 : 0.062) * (1 + 0.10 * f)
        let belly = w(0.012) * f

        var torso: [Section] = [
            Section(center: [0, w(0.465), -w(0.004)], rx: hip * 0.80, rz: hipDepth * 0.80),
            Section(center: [0, w(0.515), -w(0.004)], rx: hip, rz: hipDepth),
            Section(center: [0, w(0.570), belly * 0.6], rx: (hip + waist) / 2, rz: bellyDepth * 0.98),
            Section(center: [0, w(0.615), belly], rx: waist, rz: bellyDepth),
            Section(center: [0, w(0.670), belly * 0.4], rx: (waist + chest) / 2, rz: (bellyDepth + chestDepth) / 2),
            Section(center: [0, w(0.725), w(0.004)], rx: chest, rz: chestDepth),
            Section(center: [0, w(0.785), 0], rx: shoulder * 0.94, rz: chestDepth * 0.86),
            Section(center: [0, w(0.815), -w(0.004)], rx: shoulder * 0.70, rz: chestDepth * 0.62),
            Section(center: [0, w(0.840), -w(0.006)], rx: w(0.045) * (1 + 0.06 * m), rz: w(0.040)),
        ]
        torso = smoothed(torso, steps: 4)

        let neckRadius = w(0.029) * (1 + 0.07 * m + 0.04 * fatPos)
        let neck: [Section] = [
            Section(center: [0, w(0.830), -w(0.006)], rx: neckRadius * 1.15, rz: neckRadius),
            Section(center: [0, w(0.880), -w(0.002)], rx: neckRadius, rz: neckRadius * 0.95),
        ]

        // Head as an egg-shaped stack of sections.
        let headCenter: SIMD3<Float> = [0, w(0.935), w(0.004)]
        let headRx = w(0.061)
        let headRz = w(0.072)
        let headHalf = w(0.067)
        var head: [Section] = []
        let headRings = 14
        for i in 0...headRings {
            let t = Float(i) / Float(headRings)
            let angle = -Float.pi / 2 + t * Float.pi
            let y = sin(angle) * headHalf
            let scale = cos(angle)
            // Narrower jaw, fuller crown.
            let taper: Float = y < 0 ? 0.86 + 0.14 * (1 + y / headHalf) : 1
            head.append(Section(center: headCenter + [0, y, 0], rx: max(headRx * scale * taper, 0.0005), rz: max(headRz * scale, 0.0005)))
        }

        // Arms hang slightly away from the body.
        let upperArm = w(0.026) * (1 + 0.14 * m + 0.12 * f)
        let elbow = w(0.019) * (1 + 0.06 * m + 0.06 * f)
        let forearm = w(0.023) * (1 + 0.10 * m + 0.06 * f)
        let wrist = w(0.0145) * (1 + 0.03 * m)
        var arms = MeshData()
        for side: Float in [-1, 1] {
            let start: SIMD3<Float> = [side * (shoulder - upperArm * 0.55), w(0.805), -w(0.006)]
            let direction = simd_normalize(SIMD3<Float>(side * 0.13, -1, 0.02))
            let along = { (distance: Float) in start + direction * w(distance) }
            let u = simd_normalize(simd_cross(direction, [0, 0, 1])) * side
            let v = simd_normalize(simd_cross(u, direction)) * side
            var arm: [Section] = [
                Section(center: along(0), rx: upperArm * 0.95, rz: upperArm * 1.05, u: u, v: v),
                Section(center: along(0.07), rx: upperArm, rz: upperArm, u: u, v: v),
                Section(center: along(0.186), rx: elbow, rz: elbow, u: u, v: v),
                Section(center: along(0.235), rx: forearm, rz: forearm * 0.92, u: u, v: v),
                Section(center: along(0.330), rx: wrist * 1.1, rz: wrist * 0.8, u: u, v: v),
                Section(center: along(0.385), rx: wrist * 1.45, rz: wrist * 0.6, u: u, v: v),
                Section(center: along(0.430), rx: wrist * 0.9, rz: wrist * 0.45, u: u, v: v),
            ]
            arm = smoothed(arm, steps: 3)
            arms.append(loft(arm))
        }

        // Legs from the hip joint to the ankle, then a foot pointing forward.
        let thigh = w(female ? 0.058 : 0.053) * (1 + 0.09 * m + (female ? 0.15 : 0.10) * f)
        let knee = w(0.031) * (1 + 0.03 * m + 0.05 * f)
        let calf = w(0.032) * (1 + 0.07 * m + 0.06 * f)
        let ankle = w(0.0165)
        var legs = MeshData()
        for side: Float in [-1, 1] {
            let x = side * hip * 0.48
            var leg: [Section] = [
                Section(center: [x, w(0.500), -w(0.004)], rx: thigh * 0.98, rz: thigh * 1.02),
                Section(center: [x * 1.02, w(0.440), 0], rx: thigh, rz: thigh * 1.04),
                Section(center: [x * 0.92, w(0.360), w(0.002)], rx: (thigh + knee) / 2 * 1.04, rz: (thigh + knee) / 2),
                Section(center: [x * 0.82, w(0.285), w(0.004)], rx: knee, rz: knee),
                Section(center: [x * 0.80, w(0.215), -w(0.004)], rx: calf, rz: calf * 1.08),
                Section(center: [x * 0.78, w(0.120), 0], rx: (calf + ankle) / 2, rz: (calf + ankle) / 2),
                Section(center: [x * 0.77, w(0.045), 0], rx: ankle, rz: ankle * 1.1),
                Section(center: [x * 0.77, w(0.022), -w(0.005)], rx: ankle * 1.1, rz: ankle * 1.4),
            ]
            leg = smoothed(leg, steps: 4)
            legs.append(loft(leg))

            let footU: SIMD3<Float> = [1, 0, 0]
            let footV: SIMD3<Float> = [0, 1, 0]
            let foot: [Section] = smoothed([
                Section(center: [x * 0.77, w(0.020), -w(0.025)], rx: w(0.020), rz: w(0.016), u: footU, v: footV),
                Section(center: [x * 0.77, w(0.020), w(0.010)], rx: w(0.022), rz: w(0.019), u: footU, v: footV),
                Section(center: [x * 0.80, w(0.015), w(0.070)], rx: w(0.026), rz: w(0.013), u: footU, v: footV),
                Section(center: [x * 0.82, w(0.010), w(0.105)], rx: w(0.022), rz: w(0.009), u: footU, v: footV),
            ], steps: 3)
            legs.append(loft(foot))
        }

        var headAndNeck = loft(head)
        headAndNeck.append(loft(neck))
        return [
            .torso: loft(torso),
            .head: headAndNeck,
            .arms: arms,
            .legs: legs,
        ]
    }

    // MARK: Geometry

    /// Catmull-Rom blend of centres and radii, `steps` sections per gap.
    static func smoothed(_ sections: [Section], steps: Int) -> [Section] {
        guard sections.count > 2, steps > 1 else { return sections }
        var result: [Section] = []
        func catmull(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
            let t2 = t * t
            let t3 = t2 * t
            return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        }
        func catmull(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
            [catmull(p0.x, p1.x, p2.x, p3.x, t), catmull(p0.y, p1.y, p2.y, p3.y, t), catmull(p0.z, p1.z, p2.z, p3.z, t)]
        }
        for i in 0..<(sections.count - 1) {
            let s0 = sections[max(i - 1, 0)]
            let s1 = sections[i]
            let s2 = sections[i + 1]
            let s3 = sections[min(i + 2, sections.count - 1)]
            for step in 0..<steps {
                let t = Float(step) / Float(steps)
                result.append(Section(
                    center: catmull(s0.center, s1.center, s2.center, s3.center, t),
                    rx: max(catmull(s0.rx, s1.rx, s2.rx, s3.rx, t), 0.0005),
                    rz: max(catmull(s0.rz, s1.rz, s2.rz, s3.rz, t), 0.0005),
                    u: simd_normalize(s1.u + (s2.u - s1.u) * t),
                    v: simd_normalize(s1.v + (s2.v - s1.v) * t)
                ))
            }
        }
        result.append(sections[sections.count - 1])
        return result
    }

    /// Joins sections into a closed tube with smooth normals pointing outwards.
    static func loft(_ sections: [Section]) -> MeshData {
        var mesh = MeshData()
        guard sections.count >= 2 else { return mesh }
        let n = segments
        for section in sections {
            for j in 0..<n {
                let angle = Float(j) / Float(n) * 2 * Float.pi
                // A slightly squarer oval than an ellipse reads more like a body.
                let c = cos(angle)
                let s = sin(angle)
                let exponent: Float = 0.85
                let x = copysign(pow(abs(c), exponent), c)
                let z = copysign(pow(abs(s), exponent), s)
                mesh.positions.append(section.center + section.u * (x * section.rx) + section.v * (z * section.rz))
            }
        }
        for i in 0..<(sections.count - 1) {
            for j in 0..<n {
                let a = UInt32(i * n + j)
                let b = UInt32(i * n + (j + 1) % n)
                let c = UInt32((i + 1) * n + j)
                let d = UInt32((i + 1) * n + (j + 1) % n)
                mesh.indices += [a, c, b, b, c, d]
            }
        }
        // Caps.
        for (ring, isStart) in [(0, true), (sections.count - 1, false)] {
            let centerIndex = UInt32(mesh.positions.count)
            mesh.positions.append(sections[ring].center)
            for j in 0..<n {
                let a = UInt32(ring * n + j)
                let b = UInt32(ring * n + (j + 1) % n)
                mesh.indices += isStart ? [centerIndex, a, b] : [centerIndex, b, a]
            }
        }
        orientOutwards(&mesh, sections: sections)
        mesh.normals = smoothNormals(positions: mesh.positions, indices: mesh.indices)
        return mesh
    }

    /// Flips the winding if the first side triangle faces into the tube.
    private static func orientOutwards(_ mesh: inout MeshData, sections: [Section]) {
        guard mesh.indices.count >= 3 else { return }
        let p0 = mesh.positions[Int(mesh.indices[0])]
        let p1 = mesh.positions[Int(mesh.indices[1])]
        let p2 = mesh.positions[Int(mesh.indices[2])]
        let normal = simd_cross(p1 - p0, p2 - p0)
        let outward = p0 - sections[0].center
        if simd_dot(normal, outward) < 0 {
            for t in stride(from: 0, to: mesh.indices.count, by: 3) {
                mesh.indices.swapAt(t + 1, t + 2)
            }
        }
    }

    static func smoothNormals(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let i0 = Int(indices[t]), i1 = Int(indices[t + 1]), i2 = Int(indices[t + 2])
            let face = simd_cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            normals[i0] += face
            normals[i1] += face
            normals[i2] += face
        }
        return normals.map { simd_length($0) > 0 ? simd_normalize($0) : [0, 1, 0] }
    }
}

extension MeshData {
    nonisolated mutating func append(_ other: MeshData) {
        let offset = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        indices += other.indices.map { $0 + offset }
    }
}
