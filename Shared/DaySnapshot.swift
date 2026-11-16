import Foundation
import Security

/// A small on-device store shared by the app and its widget.
///
/// Both targets list the same keychain access group in their entitlements, so
/// an item saved by the app can be read by the widget. The item is marked
/// "this device only": it is never synced to iCloud Keychain or included in
/// backups, and it needs no App Group.
nonisolated enum SharedStore {
    private static let service = "com.kevincsv.hidrata.shared"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func data(forKey key: String) -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data, forKey key: String) {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var item = query(key)
        item[kSecValueData as String] = data
        // Readable after the first unlock so the widget can refresh while the
        // device is locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The last known total for a day, written by the app so the widget can show
/// progress without reading Apple Health itself.
nonisolated struct DaySnapshot: Codable, Sendable, Equatable {
    var day: Date
    var totalMilliliters: Double
    var goalMilliliters: Double
    var unit: VolumeUnit

    private static let key = "daySnapshot"

    static let empty = DaySnapshot(day: .distantPast, totalMilliliters: 0, goalMilliliters: 2400, unit: .milliliters)

    /// The total for `date`, or zero when the snapshot belongs to another day.
    func total(on date: Date = .now, calendar: Calendar = .current) -> Double {
        calendar.isDate(day, inSameDayAs: date) ? totalMilliliters : 0
    }

    static func load() -> DaySnapshot {
        guard let data = SharedStore.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DaySnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SharedStore.set(data, forKey: Self.key)
    }
}
