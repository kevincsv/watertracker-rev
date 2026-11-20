import Foundation

/// The app's own Withings developer credentials, typed in by the user.
nonisolated struct WithingsCredentials: Codable, Sendable, Equatable {
    var clientID: String
    var clientSecret: String
    var redirectURI: String

    static let defaultRedirectURI = "hidratakc://withings"
}

nonisolated struct WithingsTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
    var userID: String

    var isExpired: Bool { expiry.timeIntervalSinceNow < 60 }
}

nonisolated enum WithingsError: LocalizedError, Equatable {
    /// Withings answered with a non-zero status.
    case status(Int, String?)
    case badResponse
    case notSignedIn

    /// The account must be connected again (expired or revoked access).
    var needsSignIn: Bool {
        switch self {
        case .notSignedIn: true
        case .status(let code, _): code == 401 || code == 100 || code == 101 || code == 102 || code == 200
        case .badResponse: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .status(let code, let message):
            String(localized: "Withings answered with error \(code). \(message ?? "")")
        case .badResponse:
            String(localized: "Withings sent an answer the app did not understand.")
        case .notSignedIn:
            String(localized: "Connect your Withings account first.")
        }
    }
}

/// The Withings public API: OAuth 2 and body measurements, read only.
///
/// This is one of the two places the app talks to the internet. It only talks
/// to Withings, only with the user's own credentials, and only downloads the
/// user's own scale data; nothing about the user is uploaded.
nonisolated enum WithingsAPI {
    static let authorizeEndpoint = "https://account.withings.com/oauth2_user/authorize2"
    static let tokenEndpoint = "https://wbsapi.withings.net/v2/oauth2"
    static let measureEndpoint = "https://wbsapi.withings.net/measure"

    /// Measure types, from the Withings API reference.
    static let measureTypes: [Int: BodyMetric] = [
        1: .weight,
        5: .leanMass,         // Fat-free mass
        6: .fatPercent,
        8: .fatMass,
        76: .muscleMass,
        77: .waterMass,       // Hydration
        88: .boneMass,
        170: .visceralFat,
        226: .basalMetabolicRate,
        227: .metabolicAge,
    ]
    static let heightType = 4

    static func authorizeURL(credentials: WithingsCredentials, state: String) -> URL? {
        var components = URLComponents(string: authorizeEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "scope", value: "user.metrics"),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// The `code` from the address Withings sends the browser back to, if its
    /// `state` matches.
    static func code(from callback: URL, state: String) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }

    static func exchange(code: String, credentials: WithingsCredentials, now: Date = .now) async throws -> WithingsTokens {
        let data = try await post(tokenEndpoint, form: [
            "action": "requesttoken",
            "grant_type": "authorization_code",
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "redirect_uri": credentials.redirectURI,
        ])
        return try parseTokens(data, now: now)
    }

    static func refresh(_ tokens: WithingsTokens, credentials: WithingsCredentials, now: Date = .now) async throws -> WithingsTokens {
        let data = try await post(tokenEndpoint, form: [
            "action": "requesttoken",
            "grant_type": "refresh_token",
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "refresh_token": tokens.refreshToken,
        ])
        return try parseTokens(data, now: now)
    }

    /// Every body measurement updated since `lastUpdate` (all of them if nil),
    /// plus the time to pass next time.
    static func measurements(since lastUpdate: Date?, accessToken: String) async throws -> MeasurePage {
        var all = MeasurePage(readings: [], heightMeters: nil, updateTime: nil)
        var offset: Int?
        let types = (Array(measureTypes.keys) + [heightType]).sorted().map(String.init).joined(separator: ",")
        repeat {
            var form = ["action": "getmeas", "meastypes": types, "category": "1"]
            if let lastUpdate {
                form["lastupdate"] = String(Int(lastUpdate.timeIntervalSince1970))
            }
            if let offset {
                form["offset"] = String(offset)
            }
            let data = try await post(measureEndpoint, form: form, bearer: accessToken)
            let page = try parseMeasures(data)
            all.readings += page.readings
            all.heightMeters = page.heightMeters ?? all.heightMeters
            all.updateTime = page.updateTime ?? all.updateTime
            offset = page.nextOffset
        } while offset != nil
        return all
    }

    // MARK: Parsing (pure, tested)

    struct MeasurePage: Sendable, Equatable {
        var readings: [BodyReading]
        var heightMeters: Double?
        var updateTime: Date?
        var nextOffset: Int?
    }

    private struct Envelope<Body: Decodable>: Decodable {
        let status: Int
        let body: Body?
        let error: String?
    }

    private struct TokenBody: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let userid: FlexibleString
    }

    /// Withings sends ids sometimes as numbers and sometimes as strings.
    private struct FlexibleString: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = String(number)
            } else {
                value = try container.decode(String.self)
            }
        }
    }

    private struct MeasureBody: Decodable {
        struct Group: Decodable {
            struct Measure: Decodable {
                let value: Int
                let type: Int
                let unit: Int
                /// Set on per-limb measurements, which are not used.
                let position: Int?
            }
            let date: Int
            let category: Int?
            let measures: [Measure]
        }
        let updatetime: Int?
        let measuregrps: [Group]
        let more: FlexibleBool?
        let offset: Int?
    }

    private struct FlexibleBool: Decodable {
        let value: Bool
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number != 0
            } else {
                value = try container.decode(Bool.self)
            }
        }
    }

    static func parseTokens(_ data: Data, now: Date) throws -> WithingsTokens {
        let envelope: Envelope<TokenBody>
        do {
            envelope = try JSONDecoder().decode(Envelope<TokenBody>.self, from: data)
        } catch {
            if let status = try? JSONDecoder().decode(StatusOnly.self, from: data), status.status != 0 {
                throw WithingsError.status(status.status, status.error)
            }
            throw WithingsError.badResponse
        }
        guard envelope.status == 0, let body = envelope.body else {
            throw WithingsError.status(envelope.status, envelope.error)
        }
        return WithingsTokens(
            accessToken: body.access_token,
            refreshToken: body.refresh_token,
            expiry: now.addingTimeInterval(TimeInterval(body.expires_in)),
            userID: body.userid.value
        )
    }

    private struct StatusOnly: Decodable {
        let status: Int
        let error: String?
    }

    static func parseMeasures(_ data: Data) throws -> MeasurePage {
        let envelope: Envelope<MeasureBody>
        do {
            envelope = try JSONDecoder().decode(Envelope<MeasureBody>.self, from: data)
        } catch {
            if let status = try? JSONDecoder().decode(StatusOnly.self, from: data), status.status != 0 {
                throw WithingsError.status(status.status, status.error)
            }
            throw WithingsError.badResponse
        }
        guard envelope.status == 0, let body = envelope.body else {
            throw WithingsError.status(envelope.status, envelope.error)
        }
        var readings: [BodyReading] = []
        var height: (date: Int, meters: Double)?
        for group in body.measuregrps where group.category ?? 1 == 1 {
            var reading = BodyReading(date: Date(timeIntervalSince1970: TimeInterval(group.date)), sources: [.withings])
            for measure in group.measures where measure.position == nil {
                let value = Double(measure.value) * pow(10, Double(measure.unit))
                if measure.type == heightType {
                    if height == nil || group.date > height!.date {
                        height = (group.date, value)
                    }
                } else if let metric = measureTypes[measure.type] {
                    reading[metric] = value
                }
            }
            if !reading.values.isEmpty {
                readings.append(reading)
            }
        }
        return MeasurePage(
            readings: readings,
            heightMeters: height?.meters,
            updateTime: body.updatetime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            nextOffset: (body.more?.value ?? false) ? body.offset : nil
        )
    }

    // MARK: Network

    private static func post(_ endpoint: String, form: [String: String], bearer: String? = nil) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw WithingsError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WithingsError.badResponse }
        return data
    }
}
