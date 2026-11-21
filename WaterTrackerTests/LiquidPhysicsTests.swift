import CoreGraphics
import Foundation
import Testing
@testable import WaterTracker

struct LiquidPhysicsTests {
    private static let upright = MotionInput(gravityX: 0, gravityY: -1, accelerationX: 0, accelerationY: 0, shake: 0)
    private static let upsideDown = MotionInput(gravityX: 0, gravityY: 1, accelerationX: 0, accelerationY: 0, shake: 0)

    /// Runs the water for `seconds` at 60 frames per second.
    private func run(
        _ simulation: inout LiquidSimulation,
        from start: Double = 0,
        seconds: Double,
        fill: Double,
        input: MotionInput?
    ) {
        for frame in 0...Int(seconds * 60) {
            simulation.advance(to: start + Double(frame) / 60, targetFill: fill, input: input, animated: true)
        }
    }

    private func averageY(_ simulation: LiquidSimulation) -> Double {
        simulation.fluid.y.reduce(0, +) / Double(max(simulation.fluid.count, 1))
    }

    // MARK: Screen axes

    @Test func landscapeUsesTheScreenAxes() {
        // iPad in landscape, home edge on the right, held level: gravity
        // points down the screen.
        let right = ScreenTurn.landscapeRight.screenVector(x: -1, y: 0)
        #expect(right.x == 0 && right.y == -1)
        let left = ScreenTurn.landscapeLeft.screenVector(x: 1, y: 0)
        #expect(left.x == 0 && left.y == -1)
        let flipped = ScreenTurn.upsideDown.screenVector(x: 0, y: 1)
        #expect(flipped.x == 0 && flipped.y == -1)
    }

    // MARK: Geometry

    @Test func surfaceMatchesTheAmountOfWater() {
        #expect(LiquidGeometry.surfaceOffset(fill: 0) == 1)
        #expect(LiquidGeometry.surfaceOffset(fill: 1) == -1)
        #expect(abs(LiquidGeometry.surfaceOffset(fill: 0.5)) < 1e-6)
        for fill in stride(from: 0.05, through: 0.95, by: 0.1) {
            let offset = LiquidGeometry.surfaceOffset(fill: fill)
            #expect(abs(LiquidGeometry.filledFraction(surfaceOffset: offset) - fill) < 1e-6)
        }
        #expect(LiquidGeometry.surfaceOffset(fill: 0.25) > LiquidGeometry.surfaceOffset(fill: 0.75))
    }

    // MARK: The water

    @Test func glassStartsWithTheAmountDrunk() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.3, input: nil, animated: true)
        #expect(simulation.fluid.count == LiquidSimulation.particleCount(fill: 0.3))
        // Lying at the bottom of the glass, not falling in.
        #expect(averageY(simulation) > 0.4)
    }

    @Test func waterComesToRest() {
        var simulation = LiquidSimulation()
        run(&simulation, seconds: 3, fill: 0.25, input: Self.upright)
        #expect(simulation.fluid.averageSpeed < 0.15)
        #expect(averageY(simulation) > 0.4)
    }

    @Test func waterFallsToTheOtherSideWhenTurnedOver() {
        var simulation = LiquidSimulation()
        run(&simulation, seconds: 0.5, fill: 0.25, input: Self.upright)
        run(&simulation, from: 0.5, seconds: 3, fill: 0.25, input: Self.upsideDown)
        // All of it ends up at the top of the screen: none stays stuck.
        #expect(averageY(simulation) < -0.4)
        #expect(simulation.fluid.y.allSatisfy { $0 < 0.1 })
    }

    @Test func shakingKeepsTheWaterInTheGlass() {
        var simulation = LiquidSimulation()
        for frame in 0..<120 {
            let push = frame % 20 < 10 ? 3.0 : -3.0
            let input = MotionInput(gravityX: 0.6, gravityY: -0.8, accelerationX: push, accelerationY: -push, shake: 4)
            // Uneven frame times, as on a busy phone.
            simulation.advance(to: Double(frame) * (frame % 7 == 0 ? 0.2 : 1.0 / 60), targetFill: 0.25, input: input, animated: true)
        }
        let fluid = simulation.fluid
        #expect(fluid.count == LiquidSimulation.particleCount(fill: 0.25))
        for index in 0..<fluid.count {
            let distance = (fluid.x[index] * fluid.x[index] + fluid.y[index] * fluid.y[index]).squareRoot()
            #expect(distance.isFinite && distance <= ParticleFluid.wall + 1e-9)
            #expect(fluid.vx[index].isFinite && fluid.vy[index].isFinite)
        }
    }

    @Test func drinkingPoursWaterInAndUndoingTakesItOut() {
        var simulation = LiquidSimulation()
        run(&simulation, seconds: 0.2, fill: 0.1, input: nil)
        run(&simulation, from: 0.2, seconds: 2, fill: 0.2, input: nil)
        #expect(simulation.fluid.count == LiquidSimulation.particleCount(fill: 0.2))
        #expect(simulation.fill == 0.2)
        run(&simulation, from: 2.2, seconds: 1, fill: 0.05, input: nil)
        #expect(simulation.fluid.count == LiquidSimulation.particleCount(fill: 0.05))
    }

    @Test func reduceMotionDrawsStillWater() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.4, input: nil, animated: false)
        #expect(simulation.fill == 0.4)
        #expect(simulation.isStill)
        #expect(simulation.fluid.count == 0)
    }

    // MARK: Touch

    @Test func tappingTheWaterSplashes() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.3, input: nil, animated: true)
        let size = CGSize(width: 200, height: 200)
        let hit = simulation.splash(at: CGPoint(x: 100, y: 170), in: size)
        #expect(hit)
        // Some of the water is thrown upwards.
        #expect((simulation.fluid.vy.min() ?? 0) < -1)
    }

    @Test func tappingTheEmptyPartDoesNothing() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.3, input: nil, animated: true)
        let size = CGSize(width: 200, height: 200)
        let hit = simulation.splash(at: CGPoint(x: 100, y: 40), in: size)
        #expect(!hit)
        #expect(simulation.fluid.vy.allSatisfy { $0 == 0 })
    }
}
