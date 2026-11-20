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
    var errorMessage: String?

    @ObservationIgnored private let cloud: FriendsCloud
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var latest: WaterSummary?
    @ObservationIgnored private var lastPublished: WaterSummary?

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
            } else {
                share = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called whenever your water or goal changes. Uploads only when sharing
    /// is on and something actually changed.
    func update(history: [DayTotal], goal: Double) {
        latest = mySummary(history: history, goal: goal)
        Task { await publishLatest() }
    }

    func startSharing() async {
        isSharing = true
        defaults.set(true, forKey: Key.isSharing)
        lastPublished = nil
        await publishLatest()
    }

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
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ friend: Participant) async {
        do {
            try await cloud.remove(friendID: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await cloud.accept(metadata)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
