import CloudKit
import Foundation

/// Everything that talks to iCloud for the friends feature, and the only
/// place in the app that uses CloudKit (see scripts/check-privacy.sh).
///
/// How it works: your summary lives in a zone of your own private iCloud
/// database. Inviting a friend shares that zone with them, read-only, through
/// Apple's own sharing. Friends who invite you show up in your shared
/// database. There is no server of our own and no public data: only people
/// you invite can read your summary, and stopping deletes it from iCloud.
nonisolated final class FriendsCloud: Sendable {
    static let shared = FriendsCloud()

    static let containerIdentifier = "iCloud.com.kevincsv.hidrata"
    private static let zoneName = "WaterSharing"
    private static let recordType = "WaterSummary"
    private static let recordName = "summary"
    private static let payloadKey = "payload"

    let container = CKContainer(identifier: FriendsCloud.containerIdentifier)
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    /// Requests run at user priority and give up after a short wait with a
    /// timeout error, instead of the system default of waiting for days,
    /// which made the invite sheet spin forever when something was wrong.
    private static var configuration: CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        return configuration
    }

    private func onPrivate<R>(_ body: (CKDatabase) async throws -> R) async throws -> R {
        try await privateDatabase.configuredWith(configuration: Self.configuration, body: body)
    }

    private func onShared<R>(_ body: (CKDatabase) async throws -> R) async throws -> R {
        try await sharedDatabase.configuredWith(configuration: Self.configuration, body: body)
    }
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// False when the person is not signed in to iCloud (or iCloud is off).
    func isAccountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Your own summary

    /// Saves your summary to your private zone, creating the zone if needed.
    func publish(_ summary: WaterSummary) async throws {
        try await ensureZone()
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: Self.recordName, zoneID: zoneID))
        record[Self.payloadKey] = try JSONEncoder().encode(summary) as NSData
        let (results, _) = try await onPrivate { try await $0.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys) }
        for (_, result) in results {
            _ = try result.get()
        }
    }

    /// The share that lets friends read your zone, if you have invited anyone.
    func existingShare() async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await onPrivate { try await $0.record(for: id) } as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Returns the share for your zone, creating it the first time. Only
    /// people you add can open it, and they can only read.
    func makeShare(title: String) async throws -> CKShare {
        if let share = try await existingShare() { return share }
        try await ensureZone()
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        let (results, _) = try await onPrivate { try await $0.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys) }
        guard let saved = try results[share.recordID]?.get() as? CKShare else { return share }
        return saved
    }

    /// Deletes your zone, which removes your summary from iCloud and ends the
    /// share for everyone you invited.
    func stopSharing() async throws {
        do {
            let zoneID = zoneID
            _ = try await onPrivate { try await $0.deleteRecordZone(withID: zoneID) }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return
        }
    }

    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await onPrivate { try await $0.save(zone) }
    }

    // MARK: Friends

    /// Everyone who shared their summary with you.
    func friends() async throws -> [Participant] {
        let zones = try await onShared { try await $0.allRecordZones() }.filter { $0.zoneID.zoneName == Self.zoneName }
        guard !zones.isEmpty else { return [] }
        let ids = zones.map { CKRecord.ID(recordName: Self.recordName, zoneID: $0.zoneID) }
        let results = try await onShared { try await $0.records(for: ids, desiredKeys: [Self.payloadKey]) }
        let decoder = JSONDecoder()
        return ids.compactMap { id in
            guard let record = try? results[id]?.get(),
                  let data = record[Self.payloadKey] as? Data,
                  let summary = try? decoder.decode(WaterSummary.self, from: data)
            else { return nil }
            return Participant(id: id.zoneID.ownerName, isMe: false, summary: summary)
        }
    }

    /// Stops following a friend: you leave their share and no longer see them.
    func remove(friendID: String) async throws {
        let id = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: friendID)
        _ = try await onShared { try await $0.deleteRecordZone(withID: id) }
    }

    /// Accepts an invitation a friend sent you.
    func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
    }

    // MARK: Errors

    /// A readable explanation for a CloudKit error, with the original text
    /// underneath so the real cause is always visible.
    static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        if error.code == .partialFailure, let first = error.partialErrorsByItemID?.values.first {
            return message(for: first)
        }
        let hint: String
        switch error.code {
        case .notAuthenticated:
            hint = String(localized: "You are not signed in to iCloud. Sign in in the Settings app and try again.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            hint = String(localized: "iCloud could not be reached. Check your connection and try again.")
        case .quotaExceeded:
            hint = String(localized: "Your iCloud storage is full.")
        case .badContainer, .missingEntitlement, .permissionFailure, .badDatabase:
            hint = String(localized: "The app's iCloud container is not set up in the Apple developer account.")
        case .serverRejectedRequest, .invalidArguments, .unknownItem:
            hint = String(localized: "iCloud rejected the data. The WaterSummary record type is probably missing from the Production schema in CloudKit Console.")
        default:
            hint = String(localized: "iCloud returned an error.")
        }
        return "\(hint)\n\n[\(error.code.rawValue)] \(error.localizedDescription)"
    }
}
