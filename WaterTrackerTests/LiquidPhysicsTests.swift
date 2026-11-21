import CoreGraphics
import Foundation
import Testing
@testable import WaterTracker

struct LiquidPhysicsTests {
    // MARK: Which way is down

    @Test func uprightPhoneHasWaterAtTheBottom() {
        #expect(LiquidTilt.targetAngle(gravityX: 0, gravityY: -1) == 0)
    }

    @Test func tiltingRightLeansDownToTheRight() {
        let angle = LiquidTilt.targetAngle(gravityX: 0.3, gravityY: -0.95)!
        #expect(angle > 0.25 && angle < 0.35)
        #expect(LiquidTilt.targetAngle(gravityX: -0.3, gravityY: -0.95)! == -angle)
    }

    @Test func upsideDownPutsTheWaterAtTheTop() {
        let angle = LiquidTilt.targetAngle(gravityX: 0, gravityY: 1)!
        #expect(abs(abs(angle) - .pi) < 1e-9)
    }

    @Test func flatOnATableHoldsTheWater() {
        #expect(LiquidTilt.targetAngle(gravityX: 0.05, gravityY: -0.05) == nil)
    }

    @Test func landscapeUsesTheScreenAxes() {
        // iPad in landscape, home edge on the right, held level.
        #expect(LiquidTilt.targetAngle(gravityX: -1, gravityY: 0, turn: .landscapeRight) == 0)
        #expect(LiquidTilt.targetAngle(gravityX: 1, gravityY: 0, turn: .landscapeLeft) == 0)
        #expect(LiquidTilt.targetAngle(gravityX: 0, gravityY: 1, turn: .upsideDown) == 0)
    }

    @Test func shortestTurnCrossesTheTopOfTheCircle() {
        let turn = LiquidTilt.shortestTurn(from: 3.0, to: -3.0)
        #expect(abs(turn - (2 * .pi - 6)) < 1e-9)
    }

    // MARK: The spring

    @Test func waterFallsToTheOtherSideWhenTurnedOver() {
        var tilt = LiquidTilt()
        for _ in 0..<240 {
            tilt.step(target: .pi, lateralAcceleration: 0, dt: 1 / 60)
        }
        #expect(abs(LiquidTilt.shortestTurn(from: tilt.angle, to: .pi)) < 0.01)
        #expect(abs(tilt.velocity) < 0.05)
    }

    @Test func springOvershootsLikeLiquid() {
        var tilt = LiquidTilt()
        var peak = 0.0
        for _ in 0..<60 {
            tilt.step(target: 0.5, lateralAcceleration: 0, dt: 1 / 60)
            peak = max(peak, tilt.angle)
        }
        #expect(peak > 0.5)
        #expect(peak < 0.65)
    }

    @Test func holdingKeepsTheWaterWhereItIs() {
        var tilt = LiquidTilt(angle: 0.4, velocity: 0)
        tilt.step(target: nil, lateralAcceleration: 0, dt: 1 / 60)
        #expect(tilt.angle == 0.4)
    }

    @Test func movingRightLeavesWaterOnTheLeft() {
        var tilt = LiquidTilt()
        tilt.step(target: 0, lateralAcceleration: 0.5, dt: 1 / 60)
        #expect(tilt.angle < 0)
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

    // MARK: Waves, drops and bubbles

    @Test func splashThrowsDropsAndCalmsDown() {
        var surface = WaterSurface()
        surface.splash(at: 0.2, surfaceY: 0, strength: 1)
        #expect(!surface.drops.isEmpty)
        #expect(!surface.bubbles.isEmpty)

        var deepest = 0.0
        for _ in 0..<30 {
            surface.step(dt: 1 / 60, surfaceY: 0)
            deepest = max(deepest, surface.height(at: 0.2))
        }
        #expect(deepest > 0.03)

        for _ in 0..<900 {
            surface.step(dt: 1 / 60, surfaceY: 0)
        }
        #expect(surface.drops.isEmpty)
        #expect(surface.bubbles.isEmpty)
        #expect(surface.isCalm)
    }

    @Test func wavesNeitherAddNorRemoveWater() {
        var surface = WaterSurface()
        surface.splash(at: -0.6, surfaceY: 0.3, strength: 2)
        surface.slosh(1)
        for _ in 0..<120 {
            surface.step(dt: 1 / 60, surfaceY: 0.3)
            let mean = surface.heights.reduce(0, +) / Double(surface.heights.count)
            #expect(abs(mean) < 1e-9)
        }
    }

    @Test func largeFrameGapsStayStable() {
        var surface = WaterSurface()
        surface.splash(at: 0, surfaceY: 0, strength: 2)
        for _ in 0..<50 {
            surface.step(dt: 0.5, surfaceY: 0)
        }
        #expect(surface.heights.allSatisfy { $0.isFinite && abs($0) <= WaterSurface.maxHeight })
    }

    // MARK: Whole simulation

    @Test func levelEasesTowardsTheAmountDrunk() {
        var simulation = LiquidSimulation()
        for frame in 0..<180 {
            simulation.advance(to: Double(frame) / 60, targetFill: 0.6, input: nil, animated: true)
        }
        #expect(abs(simulation.fill - 0.6) < 0.01)
    }

    @Test func reduceMotionDrawsStillWater() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.4, input: nil, animated: false)
        #expect(simulation.fill == 0.4)
        #expect(simulation.tilt == LiquidTilt())
    }

    @Test func tappingTheGlassSplashes() {
        var simulation = LiquidSimulation()
        simulation.advance(to: 0, targetFill: 0.5, input: nil, animated: false)
        simulation.splash(at: CGPoint(x: 150, y: 150), in: CGSize(width: 200, height: 200))
        #expect(!simulation.surface.drops.isEmpty)
    }
}
