import SwiftUI

/// One frame of the water, ready to draw.
nonisolated struct WaterFrame: Sendable {
    var simulation: LiquidSimulation
    var time: TimeInterval
}

/// Draws the water in the round gauge: a lighter back wave for depth, the
/// main body with a deep-to-bright gradient, a shining surface line, bubbles,
/// flying drops, and a glass reflection on top.
nonisolated enum WaterRenderer {
    /// The theme's cyan (#3FD0E8) and two deeper blues for the body.
    static let bright = Color(red: 0.247, green: 0.816, blue: 0.910)
    static let middle = Color(red: 0.090, green: 0.560, blue: 0.800)
    static let deep = Color(red: 0.020, green: 0.250, blue: 0.520)

    static func draw(_ frame: WaterFrame, in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        context.fill(circle, with: .color(bright.opacity(0.08)))

        let simulation = frame.simulation
        if simulation.fill > 0.0005 {
            var water = context
            water.clip(to: circle)
            // Work in the water's own frame: radius 1, "down" is +y.
            water.translateBy(x: center.x, y: center.y)
            water.rotate(by: .radians(-simulation.tilt.angle))
            water.scaleBy(x: radius, y: radius)
            drawWater(simulation, time: frame.time, in: &water)
        }

        // A soft reflection on the glass, which stays put as the water moves.
        var shine = Path()
        shine.addArc(center: center, radius: radius * 0.86, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        context.stroke(shine, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: radius * 0.05, lineCap: .round))
    }

    private static func drawWater(_ simulation: LiquidSimulation, time: TimeInterval, in context: inout GraphicsContext) {
        let surface = simulation.surface
        let level = simulation.surfaceOffset
        // Waves fade out in an almost empty glass so it does not flicker.
        let amplitude = min(1, simulation.fill * 10)
        let count = WaterSurface.columnCount

        func points(_ height: (Int, Double) -> Double) -> [CGPoint] {
            (0..<count).map { index in
                let x = WaterSurface.columnX(index)
                return CGPoint(x: x, y: level + amplitude * height(index, x))
            }
        }

        func body(_ top: [CGPoint]) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: -1.4, y: top[0].y))
            path.addLines(top)
            path.addLine(to: CGPoint(x: 1.4, y: top[count - 1].y))
            path.addLine(to: CGPoint(x: 1.4, y: 1.4))
            path.addLine(to: CGPoint(x: -1.4, y: 1.4))
            path.closeSubpath()
            return path
        }

        // Back wave: the same waves mirrored, a little higher and lighter.
        let back = points { index, x in
            0.7 * surface.heights[count - 1 - index] - 0.03 + 0.014 * sin(3 * x + time * 1.7)
        }
        context.fill(body(back), with: .color(bright.opacity(0.32)))

        // Main body.
        let front = points { index, x in
            surface.heights[index] + 0.008 * sin(4.2 * x - time * 2.1)
        }
        context.fill(
            body(front),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: bright.opacity(0.95), location: 0),
                    .init(color: middle, location: 0.35),
                    .init(color: deep, location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: level - 0.05),
                endPoint: CGPoint(x: 0, y: 1)
            )
        )

        // Light catching the surface.
        var line = Path()
        line.addLines(front)
        context.stroke(line, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 0.06, lineCap: .round, lineJoin: .round))
        context.stroke(line, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 0.014, lineCap: .round, lineJoin: .round))

        for bubble in surface.bubbles {
            let y = level + amplitude * surface.height(at: bubble.x) + bubble.depth
            let rect = CGRect(x: bubble.x - bubble.radius, y: y - bubble.radius, width: 2 * bubble.radius, height: 2 * bubble.radius)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.14)))
            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.55)), lineWidth: 0.006)
        }

        for drop in surface.drops {
            let rect = CGRect(x: drop.x - drop.radius, y: drop.y - drop.radius, width: 2 * drop.radius, height: 2 * drop.radius)
            context.fill(Path(ellipseIn: rect), with: .color(bright))
            let glint = CGRect(x: drop.x - drop.radius * 0.45, y: drop.y - drop.radius * 0.55, width: drop.radius * 0.5, height: drop.radius * 0.5)
            context.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.7)))
        }
    }
}
