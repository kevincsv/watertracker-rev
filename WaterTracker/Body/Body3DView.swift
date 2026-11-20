import RealityKit
import SwiftUI
import UIKit

/// The figure in 3D. Drag sideways to turn it. With `ghost`, an earlier shape
/// is drawn as a faint outline over it, to compare.
struct Body3DView: View {
    var shape: BodyShape
    var ghost: BodyShape?

    @State private var scene = BodyScene()
    @State private var yaw: Float = 0.35
    @State private var dragStart: Float?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RealityView { content in
            scene.install(in: &content)
            scene.update(shape: shape, ghost: ghost, yaw: yaw)
        } update: { _ in
            scene.update(shape: shape, ghost: ghost, yaw: yaw)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStart ?? yaw
                    dragStart = start
                    yaw = start + Float(value.translation.width) / 120
                }
                .onEnded { _ in dragStart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel(Text("3D body model"))
        .accessibilityHint(Text("Drag sideways to turn it."))
    }
}

/// Owns the RealityKit entities and rebuilds the meshes only when the shape
/// changes.
@MainActor
final class BodyScene {
    private let root = Entity()
    private let figure = Entity()
    private let ghostFigure = Entity()
    private let camera = PerspectiveCamera()
    private var parts: [BodyMesh.Part: ModelEntity] = [:]
    private var ghostParts: [BodyMesh.Part: ModelEntity] = [:]
    private var currentShape: BodyShape?
    private var currentGhost: BodyShape?
    private var installed = false

    func install(in content: inout RealityViewCameraContent) {
        guard !installed else { return }
        installed = true
        root.addChild(figure)
        root.addChild(ghostFigure)
        content.add(root)

        camera.camera.fieldOfViewInDegrees = 30
        content.add(camera)

        let key = DirectionalLight()
        key.light.intensity = 3_000
        key.look(at: [0, 1, 0], from: [1.5, 2.6, 2.5], relativeTo: nil)
        content.add(key)

        let rim = DirectionalLight()
        rim.light.intensity = 1_800
        rim.light.color = UIColor(Theme.accent)
        rim.look(at: [0, 1, 0], from: [-2, 1.6, -2], relativeTo: nil)
        content.add(rim)

        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: [0, 1, 0], from: [-1.5, 0.6, 2.5], relativeTo: nil)
        content.add(fill)
    }

    func update(shape: BodyShape, ghost: BodyShape?, yaw: Float) {
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        if shape != currentShape {
            currentShape = shape
            rebuild(shape, into: figure, parts: &parts, material: Self.bodyMaterial)
            let height = Float(shape.heightMeters)
            let distance = height * 2.15
            camera.look(at: [0, height * 0.5, 0], from: [0, height * 0.56, distance], relativeTo: nil)
        }
        if ghost != currentGhost {
            currentGhost = ghost
            if let ghost {
                ghostFigure.isEnabled = true
                rebuild(ghost, into: ghostFigure, parts: &ghostParts, material: Self.ghostMaterial)
            } else {
                ghostFigure.isEnabled = false
            }
        }
    }

    private func rebuild(_ shape: BodyShape, into parent: Entity, parts: inout [BodyMesh.Part: ModelEntity], material: any RealityKit.Material) {
        for (part, data) in BodyMesh.build(shape) {
            guard let mesh = Self.mesh(data, name: part.rawValue) else { continue }
            if let entity = parts[part] {
                entity.model?.mesh = mesh
            } else {
                let entity = ModelEntity(mesh: mesh, materials: [material])
                parent.addChild(entity)
                parts[part] = entity
            }
        }
    }

    private static func mesh(_ data: MeshData, name: String) -> MeshResource? {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.primitives = .triangles(data.indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static var bodyMaterial: any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.62, green: 0.70, blue: 0.76, alpha: 1))
        material.roughness = 0.45
        material.metallic = 0.05
        return material
    }

    private static var ghostMaterial: any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(Theme.accent))
        material.emissiveColor = .init(color: UIColor(Theme.accent))
        material.emissiveIntensity = 0.4
        material.blending = .transparent(opacity: 0.22)
        return material
    }
}
