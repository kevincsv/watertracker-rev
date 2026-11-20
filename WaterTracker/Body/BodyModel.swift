import Foundation
import Observation

/// Gathers body measurements from the Health app and, if connected, from the
/// user's Withings account, and works out the trends the Body tab shows.
@Observable
final class BodyModel {
    static let shared = BodyModel()

    /// Merged weigh-ins with derived values filled in, oldest first.
    private(set) var readings: [BodyReading] = []
    private(set) var trends: [BodyMetric: [TrendPoint]] = [:]
    private(set) var profile = BodyProfile()
    private(set) var isLoading = false
    private(set) var withingsConnected = WithingsVault.tokens != nil
    private(set) var lastWithingsSync: Date?
    var withingsError: String?

    @ObservationIgnored private var cache = WithingsCache.load()
    @ObservationIgnored private let health = BodyHealthReader.shared
    @ObservationIgnored private let askedKey = "bodyHealthAccessAsked"

    var hasAskedHealth: Bool { UserDefaults.standard.bool(forKey: askedKey) }

    init() {
        lastWithingsSync = cache.lastSync
    }

    /// Metrics with at least one reading, in display order.
    var availableMetrics: [BodyMetric] {
        BodyMetric.allCases.filter { !(trends[$0]?.isEmpty ?? true) }
    }

    var firstDate: Date? { readings.first?.date }

    func trendValue(_ metric: BodyMetric, at date: Date = .now) -> Double? {
        trends[metric].flatMap { BodyTrend.value(at: date, in: $0) }
    }

    func weeklyRate(_ metric: BodyMetric, now: Date = .now) -> Double? {
        trends[metric].flatMap { BodyTrend.weeklyRate($0, now: now) }
    }

    /// The figure's shape from the trends at `date`.
    func shape(at date: Date = .now) -> BodyShape {
        BodyComposition.shape(
            weight: trendValue(.weight, at: date),
            fatPercent: trendValue(.fatPercent, at: date),
            leanKilograms: trendValue(.leanMass, at: date),
            profile: profile
        )
    }

    /// Whether the fat percentage comes from a scale or is estimated from BMI.
    var fatIsEstimated: Bool { trends[.fatPercent]?.isEmpty ?? true }

    /// What the last four weeks of fat and lean trends say.
    var recentChange: BodyChange? {
        guard let fat = weeklyRate(.fatMass), let lean = weeklyRate(.leanMass) else { return nil }
        return BodyComposition.change(fatPerWeek: fat, leanPerWeek: lean)
    }

    // MARK: Loading

    func requestHealthAccess() async {
        UserDefaults.standard.set(true, forKey: askedKey)
        try? await health.requestAuthorization()
        await reload()
    }

    /// Reads everything again. Syncs Withings at most every 10 minutes, as
    /// Withings asks.
    func reload(forceWithings: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        if withingsConnected, forceWithings || (cache.lastSync.map { Date.now.timeIntervalSince($0) > 600 } ?? true) {
            await syncWithings()
        }

        var healthReadings: [BodyReading] = []
        if hasAskedHealth {
            healthReadings = await health.readings()
            let height = await health.latestHeightMeters()
            let settings = AppSettings.shared
            let sex: BodySex? = switch settings.sexChoice {
            case .female: .female
            case .male: .male
            case .health: health.biologicalSex()
            }
            profile = BodyProfile(sex: sex, heightMeters: height ?? cache.heightMeters, age: health.age())
        } else {
            profile.heightMeters = cache.heightMeters
        }
        rebuild(healthReadings + (withingsConnected ? cache.readings : []))
    }

    private func rebuild(_ raw: [BodyReading]) {
        let height = profile.heightMeters
        let merged = BodyMerge.merge(raw).map { $0.completed(heightMeters: height) }
        readings = merged
        var trends: [BodyMetric: [TrendPoint]] = [:]
        for metric in BodyMetric.allCases {
            let samples = BodyMerge.samples(of: metric, in: merged)
            if !samples.isEmpty {
                trends[metric] = BodyTrend.smooth(samples, noise: metric.noise)
            }
        }
        self.trends = trends
    }

    // MARK: Withings

    var withingsCredentials: WithingsCredentials? { WithingsVault.credentials }

    func saveCredentials(_ credentials: WithingsCredentials) {
        WithingsVault.credentials = credentials
    }

    /// Finishes signing in with the code Withings returned.
    func completeSignIn(code: String) async {
        guard let credentials = WithingsVault.credentials else { return }
        do {
            WithingsVault.tokens = try await WithingsAPI.exchange(code: code, credentials: credentials)
            withingsConnected = true
            withingsError = nil
            cache = WithingsCache()
            await reload(forceWithings: true)
        } catch {
            withingsError = error.localizedDescription
        }
    }

    func disconnectWithings() async {
        WithingsVault.tokens = nil
        WithingsCache.delete()
        cache = WithingsCache()
        withingsConnected = false
        lastWithingsSync = nil
        await reload()
    }

    private func syncWithings() async {
        guard let credentials = WithingsVault.credentials, var tokens = WithingsVault.tokens else { return }
        do {
            if tokens.isExpired {
                tokens = try await WithingsAPI.refresh(tokens, credentials: credentials)
                // Refresh tokens rotate: keep the new one straight away.
                WithingsVault.tokens = tokens
            }
            let page = try await WithingsAPI.measurements(since: cache.lastUpdate, accessToken: tokens.accessToken)
            cache.merge(page)
            cache.lastSync = .now
            cache.save()
            lastWithingsSync = cache.lastSync
            withingsError = nil
        } catch let error as WithingsError where error.needsSignIn {
            WithingsVault.tokens = nil
            withingsConnected = false
            withingsError = String(localized: "Withings access expired. Connect your account again.")
        } catch {
            withingsError = error.localizedDescription
        }
    }
}
