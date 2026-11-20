import Foundation
import Testing
@testable import WaterTracker

struct LiquidPhysicsTests {
    @Test func uprightPhoneKeepsWaterLevel() {
        #expect(LiquidPhysics.targetTilt(gravityX: 0, gravityY: -1) == 0)
    }

    @Test func tiltingRightRaisesWaterOnTheRight() {
        // Rolling the phone clockwise points its x axis down a little.
        let tilt = LiquidPhysics.targetTilt(gravityX: 0.3, gravityY: -0.95)
        #expect(tilt > 0.25 && tilt < 0.35)
        #expect(LiquidPhysics.targetTilt(gravityX: -0.3, gravityY: -0.95) == -tilt)
    }

    @Test func leanIsCapped() {
        #expect(LiquidPhysics.targetTilt(gravityX: 1, gravityY: 0) == LiquidPhysics.maxTilt)
        #expect(LiquidPhysics.targetTilt(gravityX: -1, gravityY: 0) == -LiquidPhysics.maxTilt)
    }

    @Test func flatOnATableOrUpsideDownIsLevel() {
        #expect(LiquidPhysics.targetTilt(gravityX: 0.05, gravityY: -0.05) == 0)
        #expect(LiquidPhysics.targetTilt(gravityX: 0.1, gravityY: 0.99) == 0)
    }

    @Test func landscapeUsesTheScreenAxes() {
        // iPad held in landscape, home edge on the right, perfectly level.
        #expect(LiquidPhysics.targetTilt(gravityX: -1, gravityY: 0, turn: .landscapeRight) == 0)
        #expect(LiquidPhysics.targetTilt(gravityX: 1, gravityY: 0, turn: .landscapeLeft) == 0)
        #expect(LiquidPhysics.targetTilt(gravityX: 0, gravityY: 1, turn: .upsideDown) == 0)
    }

    @Test func springSettlesOnTarget() {
        var physics = LiquidPhysics()
        for _ in 0..<300 {
            physics.step(target: 0.4, lateralAcceleration: 0, shake: 0, dt: 1 / 30)
        }
        #expect(abs(physics.tilt - 0.4) < 0.01)
        #expect(abs(physics.velocity) < 0.01)
        #expect(physics.slosh < 0.05)
    }

    @Test func springOvershootsLikeLiquid() {
        var physics = LiquidPhysics()
        var peak = 0.0
        for _ in 0..<60 {
            physics.step(target: 0.3, lateralAcceleration: 0, shake: 0, dt: 1 / 30)
            peak = max(peak, physics.tilt)
        }
        #expect(peak > 0.3)
    }

    @Test func movingRightLeavesWaterOnTheLeft() {
        var physics = LiquidPhysics()
        physics.step(target: 0, lateralAcceleration: 0.5, shake: 0.5, dt: 1 / 30)
        #expect(physics.tilt < 0)
        #expect(physics.slosh > 0.5)
    }

    @Test func splashFadesAway() {
        var physics = LiquidPhysics()
        physics.splash()
        #expect(physics.slosh == 1)
        for _ in 0..<150 {
            physics.step(target: 0, lateralAcceleration: 0, shake: 0, dt: 1 / 30)
        }
        #expect(physics.slosh < 0.1)
    }
}
