import Foundation
import Testing
@testable import WaterTracker

struct BodyTrendTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func day(_ offset: Double) -> Date {
        start.addingTimeInterval(offset * 86_400)
    }

    @Test func steadyReadingsGiveAFlatTrend() {
        let samples = (0..<20).map { BodySample(date: day(Double($0)), value: 80) }
        let points = BodyTrend.smooth(samples, noise: 0.6)
        #expect(points.count == 20)
        #expect(points.allSatisfy { abs($0.trend - 80) < 0.0001 && !$0.isOutlier })
    }

    @Test func noiseIsSmoothed() {
        // Alternating ±0.8 kg around 80 kg.
        let samples = (0..<30).map { BodySample(date: day(Double($0)), value: 80 + ($0 % 2 == 0 ? 0.8 : -0.8)) }
        let points = BodyTrend.smooth(samples, noise: 0.6)
        let last = points.suffix(10)
        #expect(last.allSatisfy { abs($0.trend - 80) < 0.35 })
    }

    @Test func aSingleBadReadingIsIgnored() {
        var samples = (0..<15).map { BodySample(date: day(Double($0)), value: 80) }
        samples[10].value = 86
        let points = BodyTrend.smooth(samples, noise: 0.6)
        #expect(points[10].isOutlier)
        #expect(abs(points[14].trend - 80) < 0.0001)
    }

    @Test func aRealStepIsFollowed() {
        let samples = (0..<40).map { BodySample(date: day(Double($0)), value: $0 < 15 ? 80 : 84) }
        let points = BodyTrend.smooth(samples, noise: 0.6)
        #expect(!points[15].isOutlier)
        #expect(points.last!.trend > 83.5)
    }

    @Test func trendFollowsALinearLoss() {
        // Losing 0.5 kg a week, weighed daily.
        let samples = (0..<56).map { BodySample(date: day(Double($0)), value: 85 - Double($0) * 0.5 / 7) }
        let points = BodyTrend.smooth(samples, noise: 0.6)
        let rate = BodyTrend.weeklyRate(points, now: day(55))
        #expect(rate != nil)
        #expect(abs(rate! + 0.5) < 0.05)
    }

    @Test func gapsCountByTime() {
        // A month away pulls the trend almost all the way to the new value.
        let samples = [BodySample(date: day(0), value: 80), BodySample(date: day(1), value: 80),
                       BodySample(date: day(2), value: 80), BodySample(date: day(3), value: 80),
                       BodySample(date: day(4), value: 80), BodySample(date: day(5), value: 80),
                       BodySample(date: day(35), value: 81)]
        let points = BodyTrend.smooth(samples, noise: 0.6)
        #expect(points.last!.trend > 80.9)
    }

    @Test func valueAtInterpolates() {
        let points = [
            TrendPoint(date: day(0), raw: 80, trend: 80, isOutlier: false),
            TrendPoint(date: day(10), raw: 78, trend: 78, isOutlier: false),
        ]
        #expect(BodyTrend.value(at: day(-1), in: points) == nil)
        #expect(abs(BodyTrend.value(at: day(5), in: points)! - 79) < 0.0001)
        #expect(BodyTrend.value(at: day(20), in: points) == 78)
    }

    @Test func weeklyRateNeedsAWeek() {
        let points = (0..<3).map { TrendPoint(date: day(Double($0)), raw: 80, trend: 80, isOutlier: false) }
        #expect(BodyTrend.weeklyRate(points, now: day(3)) == nil)
    }
}

struct BodyMergeTests {
    private let t = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func readingsOfOneWeighInAreMergedPreferringWithings() {
        var health = BodyReading(date: t, sources: [.health])
        health[.weight] = 80.1
        health[.fatPercent] = 18
        var withings = BodyReading(date: t.addingTimeInterval(30), sources: [.withings])
        withings[.weight] = 80.12
        withings[.muscleMass] = 62
        var later = BodyReading(date: t.addingTimeInterval(86_400), sources: [.health])
        later[.weight] = 79.9

        let merged = BodyMerge.merge([later, withings, health])
        #expect(merged.count == 2)
        #expect(merged[0][.weight] == 80.12)
        #expect(merged[0][.fatPercent] == 18)
        #expect(merged[0][.muscleMass] == 62)
        #expect(merged[0].sources == [.health, .withings])
    }

    @Test func derivedValuesAreFilledIn() {
        var reading = BodyReading(date: t)
        reading[.weight] = 80
        reading[.fatPercent] = 20
        let completed = reading.completed(heightMeters: 2)
        #expect(completed[.fatMass] == 16)
        #expect(completed[.leanMass] == 64)
        #expect(completed[.bmi] == 20)
    }
}

struct BodyCompositionTests {
    @Test func deurenbergEstimate() {
        // BMI 25, 30-year-old man: 1.2*25 + 0.23*30 - 10.8 - 5.4 = 20.7
        let value = BodyComposition.estimatedFatPercent(bmi: 25, age: 30, sex: .male)
        #expect(abs(value - 20.7) < 0.001)
    }

    @Test func normalizedFFMI() {
        // 64 kg lean at 1.80 m: 64 / 3.24 = 19.75, no height correction.
        let value = BodyComposition.normalizedFFMI(leanKilograms: 64, heightMeters: 1.8)
        #expect(abs(value - 19.753) < 0.01)
    }

    @Test func fatBands() {
        #expect(FatBand.band(percent: 12, sex: .male) == .athletic)
        #expect(FatBand.band(percent: 22, sex: .male) == .average)
        #expect(FatBand.band(percent: 22, sex: .female) == .fit)
        #expect(FatBand.band(percent: 35, sex: .female) == .high)
    }

    @Test func changes() {
        #expect(BodyComposition.change(fatPerWeek: -0.3, leanPerWeek: 0.1) == .recomposition)
        #expect(BodyComposition.change(fatPerWeek: -0.4, leanPerWeek: -0.15) == .cutting)
        #expect(BodyComposition.change(fatPerWeek: -0.1, leanPerWeek: -0.4) == .losingLean)
        #expect(BodyComposition.change(fatPerWeek: 0.05, leanPerWeek: 0.2) == .leanGain)
        #expect(BodyComposition.change(fatPerWeek: 0.3, leanPerWeek: 0.2) == .bulking)
        #expect(BodyComposition.change(fatPerWeek: 0.3, leanPerWeek: -0.05) == .gainingFat)
        #expect(BodyComposition.change(fatPerWeek: 0.02, leanPerWeek: -0.03) == .stable)
    }

    @Test func shapeFollowsComposition() {
        let profile = BodyProfile(sex: .male, heightMeters: 1.8, age: 30)
        let lean = BodyComposition.shape(weight: 80, fatPercent: 10, leanKilograms: 72, profile: profile)
        let soft = BodyComposition.shape(weight: 95, fatPercent: 30, leanKilograms: 66.5, profile: profile)
        #expect(lean.fat < 0)
        #expect(lean.muscle > 0)
        #expect(soft.fat > 1)
        #expect(soft.muscle < lean.muscle)
    }
}

struct BodyMeshTests {
    @Test func meshIsValidAndWidensWithFat() {
        let thin = BodyMesh.build(BodyShape(heightMeters: 1.8, sex: .male, fat: -1, muscle: 0))
        let wide = BodyMesh.build(BodyShape(heightMeters: 1.8, sex: .male, fat: 2, muscle: 0))
        for part in BodyMesh.Part.allCases {
            let mesh = thin[part]!
            #expect(!mesh.positions.isEmpty)
            #expect(mesh.positions.count == mesh.normals.count)
            #expect(mesh.indices.count % 3 == 0)
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
            #expect(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        func waistWidth(_ mesh: MeshData) -> Float {
            let band = mesh.positions.filter { abs($0.y - 0.615 * 1.8) < 0.02 }
            return (band.map(\.x).max() ?? 0) - (band.map(\.x).min() ?? 0)
        }
        #expect(waistWidth(wide[.torso]!) > waistWidth(thin[.torso]!) * 1.3)
        let top = thin.values.flatMap(\.positions).map(\.y).max()!
        #expect(abs(top - 1.8) < 0.03)
    }

    @Test func normalsPointOutwards() {
        let mesh = BodyMesh.build(BodyShape(heightMeters: 1.75, sex: .female))[.torso]!
        // On the front of the waist the normal must point forward (+z).
        let front = zip(mesh.positions, mesh.normals)
            .filter { abs($0.0.y - 0.615 * 1.75) < 0.02 && abs($0.0.x) < 0.01 && $0.0.z > 0 }
        #expect(!front.isEmpty)
        #expect(front.allSatisfy { $0.1.z > 0.5 })
    }
}

struct WithingsAPITests {
    @Test func parsesMeasurements() throws {
        let json = """
        {"status":0,"body":{"updatetime":1780000500,"timezone":"Europe/London","more":0,"offset":0,
         "measuregrps":[
          {"grpid":1,"attrib":0,"date":1780000000,"created":1780000010,"category":1,"measures":[
            {"value":80125,"type":1,"unit":-3},{"value":1810,"type":6,"unit":-2},
            {"value":6200,"type":76,"unit":-2},{"value":45,"type":170,"unit":-1},
            {"value":180,"type":4,"unit":-2},{"value":350,"type":175,"unit":-2,"position":2}]},
          {"grpid":2,"attrib":0,"date":1780086400,"category":2,"measures":[{"value":75000,"type":1,"unit":-3}]}
         ]}}
        """
        let page = try WithingsAPI.parseMeasures(Data(json.utf8))
        #expect(page.readings.count == 1)
        let reading = page.readings[0]
        #expect(abs(reading[.weight]! - 80.125) < 0.0001)
        #expect(abs(reading[.fatPercent]! - 18.1) < 0.0001)
        #expect(abs(reading[.muscleMass]! - 62) < 0.0001)
        #expect(abs(reading[.visceralFat]! - 4.5) < 0.0001)
        #expect(reading.sources == [.withings])
        #expect(abs(page.heightMeters! - 1.8) < 0.0001)
        #expect(page.updateTime == Date(timeIntervalSince1970: 1_780_000_500))
        #expect(page.nextOffset == nil)
    }

    @Test func paginates() throws {
        let json = #"{"status":0,"body":{"updatetime":1,"measuregrps":[],"more":1,"offset":200}}"#
        #expect(try WithingsAPI.parseMeasures(Data(json.utf8)).nextOffset == 200)
    }

    @Test func parsesTokensAndErrors() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let ok = #"{"status":0,"body":{"userid":12345,"access_token":"a","refresh_token":"r","expires_in":10800,"scope":"user.metrics","token_type":"Bearer"}}"#
        let tokens = try WithingsAPI.parseTokens(Data(ok.utf8), now: now)
        #expect(tokens == WithingsTokens(accessToken: "a", refreshToken: "r", expiry: now.addingTimeInterval(10_800), userID: "12345"))

        let failed = #"{"status":401,"body":{},"error":"invalid_token"}"#
        #expect(throws: WithingsError.status(401, "invalid_token")) {
            try WithingsAPI.parseTokens(Data(failed.utf8), now: now)
        }
    }

    @Test func callbackCodeNeedsMatchingState() {
        let url = URL(string: "hidratakc://withings?code=abc&state=xyz")!
        #expect(WithingsAPI.code(from: url, state: "xyz") == "abc")
        #expect(WithingsAPI.code(from: url, state: "other") == nil)
    }
}
