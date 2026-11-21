import SwiftUI

/// One frame of the water, ready to draw.
nonisolated struct WaterFrame: Sendable {
    var simulation: LiquidSimulation
}

/// Draws the water in the round gauge. Every particle is a soft dot; blurring
/// the dots together and cutting the blur off at half strength turns them
/// into one smooth body of liquid, with loose drops where particles fly free.
/// The body gets a deep-to-bright gradient and a light rim on its surface.
nonisolated enum WaterRenderer {
    /// The theme's cyan (#3FD0E8) and two deeper blues for the body.
    static let bright = Color(red: 0.247, green: 0.816, blue: 0.910)
    static let middle = Color(red: 0.090, green: 0.560, blue: 0.800)
    static let deep = Color(red: 0.020, green: 0.250, blue: 0.520)
    static let rim = Color(red: 0.62, green: 0.93, blue: 0.99)

    /// Size of each particle's dot and of the blur that joins them, in
    /// glass radii.
    static let dotRadius = 0.055
    static let blurRadius = 0.035

    static func draw(_ frame: WaterFrame, in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        context.fill(circle, with: .color(bright.opacity(0.08)))

        let simulation = frame.simulation
        var water = context
        water.clip(to: circle)
        if simulation.isStill {
            drawStill(simulation, in: &water, center: center, radius: radius)
        } else if simulation.fluid.count > 0 {
            drawFluid(simulation, in: &water, circle: circle, center: center, radius: radius)
        }

        // A soft reflection on the glass, which stays put as the water moves.
        var shine = Path()
        shine.addArc(center: center, radius: radius * 0.86, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        context.stroke(shine, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: radius * 0.05, lineCap: .round))
    }

    private static func gradient(center: CGPoint, radius: CGFloat, downX: Double, downY: Double) -> GraphicsContext.Shading {
        let length = max((downX * downX + downY * downY).squareRoot(), 1e-6)
        let x = CGFloat(downX / length) * radius
        let y = CGFloat(downY / length) * radius
        return .linearGradient(
            Gradient(stops: [
                .init(color: bright, location: 0),
                .init(color: middle, location: 0.45),
                .init(color: deep, location: 1),
            ]),
            startPoint: CGPoint(x: center.x - x, y: center.y - y),
            endPoint: CGPoint(x: center.x + x, y: center.y + y)
        )
    }

    private static func drawFluid(
        _ simulation: LiquidSimulation,
        in context: inout GraphicsContext,
        circle: Path,
        center: CGPoint,
        radius: CGFloat
    ) {
        let fluid = simulation.fluid
        let dot = CGFloat(dotRadius) * radius
        var dots = Path()
        for index in 0..<fluid.count {
            dots.addEllipse(in: CGRect(
                x: center.x + CGFloat(fluid.x[index]) * radius - dot,
                y: center.y + CGFloat(fluid.y[index]) * radius - dot,
                width: 2 * dot,
                height: 2 * dot
            ))
        }
        let blur = CGFloat(blurRadius) * radius

        // The liquid's outline, a touch larger than the body, in a light
        // colour: it shows as a bright rim along the surface.
        context.drawLayer { layer in
            layer.addFilter(.alphaThreshold(min: 0.3, color: rim.opacity(0.85)))
            layer.addFilter(.blur(radius: blur))
            layer.drawLayer { inner in
                inner.fill(dots, with: .color(.white))
            }
        }

        // The body, nudged a little "down" so the rim shows on top, then
        // coloured by painting the gradient only where the body is.
        let length = max((simulation.downX * simulation.downX + simulation.downY * simulation.downY).squareRoot(), 1e-6)
        let nudge = CGSize(
            width: CGFloat(simulation.downX / length) * radius * 0.014,
            height: CGFloat(simulation.downY / length) * radius * 0.014
        )
        let shading = gradient(center: center, radius: radius, downX: simulation.downX, downY: simulation.downY)
        context.drawLayer { body in
            body.drawLayer { shape in
                shape.translateBy(x: nudge.width, y: nudge.height)
                shape.addFilter(.alphaThreshold(min: 0.5, color: .white))
                shape.addFilter(.blur(radius: blur))
                shape.drawLayer { inner in
                    inner.fill(dots, with: .color(.white))
                }
            }
            body.blendMode = .sourceAtop
            body.fill(circle, with: shading)
        }
    }

    /// Flat, still water for Reduce Motion: the same amount, no movement.
    private static func drawStill(_ simulation: LiquidSimulation, in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard simulation.fill > 0.0005 else { return }
        let level = center.y + CGFloat(simulation.surfaceOffset) * radius
        let body = Path(CGRect(x: center.x - radius, y: level, width: 2 * radius, height: center.y + radius - level))
        context.fill(body, with: gradient(center: center, radius: radius, downX: 0, downY: 1))

        var line = Path()
        line.move(to: CGPoint(x: center.x - radius, y: level))
        line.addLine(to: CGPoint(x: center.x + radius, y: level))
        context.stroke(line, with: .color(rim.opacity(0.85)), lineWidth: max(radius * 0.014, 1))
    }
}
