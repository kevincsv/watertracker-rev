//  Based on Wave.swift from the original WaterTracker project by Yu Liang (MIT),
//  itself adapted from RedDragonJ/Swift-Learning.

import SwiftUI

/// A filled area whose top edge is a sine wave. `level` is how full it is,
/// from 0 to 1, and animates smoothly when it changes.
nonisolated struct Wave: Shape {
    var phase: Angle
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(level, 0), 1)
        let waveHeight = 0.02 * rect.height
        let surface = CGFloat(1 - clamped) * (rect.height - 2 * waveHeight) + waveHeight

        path.move(to: CGPoint(x: 0, y: surface + waveHeight * CGFloat(sin(phase.radians))))
        for degrees in stride(from: 0.0, through: 360.0, by: 6) {
            let x = CGFloat(degrees / 360) * rect.width
            let y = surface + waveHeight * CGFloat(sin(phase.radians + degrees * .pi / 180))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
