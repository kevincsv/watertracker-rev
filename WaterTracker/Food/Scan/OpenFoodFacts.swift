import Foundation

/// Looks up packaged foods by barcode in Open Food Facts, a free, open
/// database with many UK products. This is the app's only network access:
/// the request contains the barcode number and nothing about the user.
nonisolated enum OpenFoodFacts {
    nonisolated enum LookupError: LocalizedError {
        case notFound
        case noNutrition
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notFound:
                String(localized: "Este producto no está en Open Food Facts. Prueba a leer la etiqueta.")
            case .noNutrition:
                String(localized: "El producto está en Open Food Facts pero sin calorías. Prueba a leer la etiqueta.")
            case .unavailable:
                String(localized: "Open Food Facts no responde ahora mismo. Prueba más tarde o lee la etiqueta.")
            }
        }
    }

    static func lookup(barcode: String) async throws -> NutritionFacts {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json")
        else { throw LookupError.notFound }
        components.queryItems = [
            URLQueryItem(name: "fields", value: "product_name,product_name_en,brands,nutriments,serving_quantity"),
        ]
        guard let url = components.url else { throw LookupError.notFound }

        var request = URLRequest(url: url, timeoutInterval: 15)
        // Open Food Facts asks apps to identify themselves; no personal data.
        request.setValue("WaterTrackerKC (iOS)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw LookupError.notFound }
            // Busy or down: say so, instead of failing to read an error page.
            guard (200..<300).contains(http.statusCode) else { throw LookupError.unavailable }
        }
        return try parse(data)
    }

    /// Turns an Open Food Facts product response into nutrition facts.
    static func parse(_ data: Data) throws -> NutritionFacts {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["product"] as? [String: Any]
        else { throw LookupError.notFound }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        func number(_ key: String) -> Double? {
            switch nutriments[key] {
            case let value as Double: value
            case let value as Int: Double(value)
            case let value as String: NumberInput.parse(value)
            default: nil
            }
        }

        func facts(_ suffix: String) -> Nutrients? {
            let kcal = number("energy-kcal_\(suffix)")
                ?? number("energy-kj_\(suffix)").map { ($0 / 4.184).rounded() }
                ?? number("energy_\(suffix)").map { ($0 / 4.184).rounded() }
            guard let kcal else { return nil }
            return Nutrients(
                kcal: kcal,
                protein: number("proteins_\(suffix)") ?? 0,
                carbs: number("carbohydrates_\(suffix)") ?? 0,
                fat: number("fat_\(suffix)") ?? 0
            )
        }

        let per100 = facts("100g")
        let perServing = facts("serving")
        guard per100 != nil || perServing != nil else { throw LookupError.noNutrition }

        let rawName = (product["product_name_en"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? product["product_name"] as? String
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        var name = rawName?.trimmingCharacters(in: .whitespaces)
        if let brand, !brand.isEmpty, let current = name, !current.localizedCaseInsensitiveContains(brand) {
            name = "\(current) (\(brand))"
        }

        let serving: Double? = switch product["serving_quantity"] {
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as String: NumberInput.parse(value)
        default: nil
        }

        return NutritionFacts(
            name: name.flatMap { $0.isEmpty ? nil : $0 },
            per100: per100,
            perServing: perServing,
            servingSize: serving.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}
