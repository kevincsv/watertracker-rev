import Foundation
import Security

/// Keeps the Withings credentials and tokens in the keychain, on this device
/// only: never in iCloud Keychain, backups or the settings that sync.
nonisolated enum WithingsVault {
    private static let service = "com.kevincsv.hidrata.withings"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func load<Value: Decodable>(_ account: String) -> Value? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func save(_ value: (some Encodable)?, _ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static var credentials: WithingsCredentials? {
        get { load("credentials") }
        set { save(newValue, "credentials") }
    }

    static var tokens: WithingsTokens? {
        get { load("tokens") }
        set { save(newValue, "tokens") }
    }
}

/// The measurements already downloaded from Withings, so the screen works
/// offline and each sync only asks for what changed. Stored in the app's own
/// files with complete file protection.
nonisolated struct WithingsCache: Codable, Sendable {
    var readings: [BodyReading] = []
    var heightMeters: Double?
    var lastUpdate: Date?
    var lastSync: Date?

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "withings-measurements.json")
    }

    static func load() -> WithingsCache {
        guard let data = try? Data(contentsOf: url) else { return WithingsCache() }
        return (try? JSONDecoder().decode(WithingsCache.self, from: data)) ?? WithingsCache()
    }

    func save() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtection])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Adds newly downloaded readings, replacing any with the same time.
    mutating func merge(_ page: WithingsAPI.MeasurePage) {
        let newDates = Set(page.readings.map(\.date))
        readings = (readings.filter { !newDates.contains($0.date) } + page.readings).sorted { $0.date < $1.date }
        heightMeters = page.heightMeters ?? heightMeters
        lastUpdate = page.updateTime ?? lastUpdate
    }
}
