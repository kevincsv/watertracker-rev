//  Based on Wave.swift from the original WaterTracker project by Yu Liang (MIT),
//  itself adapted from RedDragonJ/Swift-Learning.

import SwiftUI

/// A filled area whose top edge is a sine wave. `level` is how full it is,
/// from 0 to 1, and animates smoothly when it changes. `tilt` leans the
/// surface (radians, positive = right side higher) and `slosh` (0...1) makes
/// the waves taller, so the water can follow the phone's movement.
nonisolated struct Wave: Shape {
    var phase: Angle
    var level: Double
    var tilt: Double = 0
    var slosh: Double = 0

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(level, 0), 1)
        let baseHeight = 0.02 * rect.height
        let waveHeight = baseHeight * CGFloat(1 + 2.5 * min(max(slosh, 0), 1))
        let surface = CGFloat(1 - clamped) * (rect.height - 2 * baseHeight) + baseHeight
        let lean = CGFloat(tan(tilt))

        func height(at degrees: Double) -> CGFloat {
            let x = CGFloat(degrees / 360) * rect.width
            return surface - (x - rect.midX) * lean
                + waveHeight * CGFloat(sin(phase.radians + degrees * .pi / 180))
        }

        path.move(to: CGPoint(x: 0, y: height(at: 0)))
        for degrees in stride(from: 0.0, through: 360.0, by: 6) {
            let x = CGFloat(degrees / 360) * rect.width
            path.addLine(to: CGPoint(x: x, y: height(at: degrees)))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
