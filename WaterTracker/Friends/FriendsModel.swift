import CloudKit
import Foundation
import Observation

/// State for the Friends tab: whether you share, your name, your friends'
/// summaries, and the actions that change them.
@MainActor
@Observable
final class FriendsModel {
    static let shared = FriendsModel()

    /// Whether your summary is uploaded to your iCloud for friends to see.
    private(set) var isSharing: Bool
    /// The name friends see next to your numbers.
    var displayName: String {
        didSet {
            defaults.set(displayName, forKey: Key.displayName)
            Task { await publishLatest() }
        }
    }
    private(set) var friends: [Participant] = []
    private(set) var share: CKShare?
    private(set) var accountAvailable = true
    private(set) var isLoading = false
    /// True while turning sharing on or preparing an invitation.
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let cloud: FriendsCloud
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var latest: WaterSummary?
    @ObservationIgnored private var lastPublished: WaterSummary?
    @ObservationIgnored private var lastPublishError: String?

    private enum Key {
        static let isSharing = "friendsSharing"
        static let displayName = "friendsDisplayName"
    }

    init(cloud: FriendsCloud = .shared, defaults: UserDefaults = .standard) {
        self.cloud = cloud
        self.defaults = defaults
        self.isSharing = defaults.bool(forKey: Key.isSharing)
        self.displayName = defaults.string(forKey: Key.displayName) ?? ""
    }

    var container: CKContainer { cloud.container }

    /// The name to show for you: what you typed, or "Me".
    var myName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Me") : trimmed
    }

    /// Your own numbers from Apple Health, in the shape friends receive.
    func mySummary(history: [DayTotal], goal: Double) -> WaterSummary {
        WaterSummary(name: myName, goalMilliliters: goal, history: history)
    }

    /// Reloads friends and the state of your share from iCloud.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        accountAvailable = await cloud.isAccountAvailable()
        guard accountAvailable else { return }
        do {
            friends = try await cloud.friends()
            if isSharing {
                share = try await cloud.existingShare()
                if share == nil {
                    // Sharing was turned on before the share existed (for
                    // example by an older build); create it now.
                    share = try await cloud.makeShare(title: shareTitle)
                }
            } else {
                share = nil
            }
        } catch {
            errorMessage = FriendsCloud.message(for: error)
        }
    }

    /// Called whenever your water or goal changes. Uploads only when sharing
    /// is on and something actually changed.
    func update(history: [DayTotal], goal: Double) {
        latest = mySummary(history: history, goal: goal)
        Task { await publishLatest() }
    }

    /// Creates your sharing zone, the invitation and the first upload. Only
    /// counts as on once all of that worked; on failure it cleans up and
    /// shows the real reason.
    func startSharing() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await cloud.makeShare(title: shareTitle)
            if var summary = latest {
                summary.name = myName
                summary.updatedAt = .now
                try await cloud.publish(summary)
                lastPublished = summary
            }
            self.share = share
            isSharing = true
            defaults.set(true, forKey: Key.isSharing)
        } catch {
            errorMessage = FriendsCloud.message(for: error)
            try? await cloud.stopSharing()
            share = nil
            lastPublished = nil
        }
    }

    /// Makes sure the invitation exists, so the invite button can show it.
    func prepareInvite() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            share = try await cloud.makeShare(title: shareTitle)
        } catch {
            errorMessage = FriendsCloud.message(for: error)
        }
    }

    private var shareTitle: String { String(localized: "\(myName)'s water") }

    /// Turns sharing off and deletes your summary from iCloud, so friends
    /// stop seeing you. Friends who shared with you stay.
    func stopSharing() async {
        do {
            try await cloud.stopSharing()
            isSharing = false
            defaults.set(false, forKey: Key.isSharing)
            share = nil
            lastPublished = nil
        } catch {
            errorMessage = FriendsCloud.message(for: error)
        }
    }

    func remove(_ friend: Participant) async {
        do {
            try await cloud.remove(friendID: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = FriendsCloud.message(for: error)
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await cloud.accept(metadata)
            await refresh()
        } catch {
            errorMessage = FriendsCloud.message(for: error)
        }
    }

    private func publishLatest() async {
        guard isSharing, accountAvailable, var summary = latest else { return }
        summary.name = myName
        if let lastPublished, lastPublished.hasSameContent(as: summary) { return }
        summary.updatedAt = .now
        do {
            try await cloud.publish(summary)
            lastPublished = summary
            lastPublishError = nil
        } catch {
            // Background uploads happen on every change; report each
            // distinct problem once instead of on every glass of water.
            let message = FriendsCloud.message(for: error)
            if message != lastPublishError {
                lastPublishError = message
                errorMessage = message
            }
        }
    }
}
