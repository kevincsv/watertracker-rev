import Foundation

/// One line of text read from a photo, with its position. Coordinates are
/// normalised to 0...1 with y growing downwards.
nonisolated struct TextLine: Hashable, Sendable {
    let text: String
    let minX: Double
    let minY: Double
    let height: Double

    var midY: Double { minY + height / 2 }
}

/// Nutrition values from a label, a barcode lookup or an estimate.
nonisolated struct NutritionFacts: Hashable, Sendable {
    var name: String?
    /// Values per 100 g or 100 ml, the first column on UK and EU labels.
    var per100: Nutrients?
    /// Values per serving, when the label has that column.
    var perServing: Nutrients?
    /// Serving size in grams or millilitres, when printed.
    var servingSize: Double?
    /// Extra information to show, such as the portions an estimate assumed.
    var note: String?

    var isEmpty: Bool { per100 == nil && perServing == nil }
}

/// Reads UK/EU nutrition tables ("Typical values / Per 100g / Per serving").
nonisolated enum LabelParser {
    static func parse(_ lines: [TextLine]) -> NutritionFacts {
        let rows = groupIntoRows(lines)
        var columns: [[Double]] = [[], [], [], []] // kcal, protein, carbs, fat
        var servingSize: Double?

        for (index, row) in rows.enumerated() {
            let lower = row.lowercased()
            if servingSize == nil {
                servingSize = parseServingSize(lower)
            }
            if lower.contains("kcal") {
                let kcal = kcalValues(lower)
                if !kcal.isEmpty, columns[0].isEmpty {
                    columns[0] = kcal
                }
                continue
            }
            guard let nutrient = nutrientIndex(lower), columns[nutrient].isEmpty else { continue }
            var values = gramValues(lower)
            // Some tables put the numbers on the line under the name.
            if values.isEmpty, index + 1 < rows.count, nutrientIndex(rows[index + 1].lowercased()) == nil {
                values = gramValues(rows[index + 1].lowercased())
            }
            columns[nutrient] = values
        }

        // Energy printed only in kJ: convert.
        if columns[0].isEmpty {
            for row in rows where row.lowercased().contains("kj") {
                let kj = numbers(in: row.lowercased(), followedBy: "kj")
                if !kj.isEmpty {
                    columns[0] = kj.map { ($0 / 4.184).rounded() }
                    break
                }
            }
        }

        func column(_ i: Int) -> Nutrients? {
            guard let kcal = columns[0].count > i ? columns[0][i] : nil else { return nil }
            func value(_ n: Int) -> Double { columns[n].count > i ? columns[n][i] : 0 }
            return Nutrients(kcal: kcal, protein: value(1), carbs: value(2), fat: value(3))
        }
        return NutritionFacts(name: nil, per100: column(0), perServing: column(1), servingSize: servingSize)
    }

    /// Joins lines that sit at the same height, left to right, top to bottom.
    static func groupIntoRows(_ lines: [TextLine]) -> [String] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.midY < $1.midY }) {
            if let last = rows.last?.last, abs(last.midY - line.midY) < max(last.height, line.height) * 0.6 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }

    /// 0 kcal, 1 protein, 2 carbohydrate, 3 fat. Sub-rows such as
    /// "of which sugars" or "saturates" are ignored.
    static func nutrientIndex(_ lower: String) -> Int? {
        let text = lower.trimmingCharacters(in: .whitespaces)
        if text.contains("of which") || text.contains("saturat") || text.contains("sugar")
            || text.contains("mono") || text.contains("poly") || text.hasPrefix("-") {
            return nil
        }
        if text.hasPrefix("protein") { return 1 }
        if text.hasPrefix("carbohydrate") || text.hasPrefix("carbs") { return 2 }
        if text.hasPrefix("fat") || text.hasPrefix("total fat") { return 3 }
        return nil
    }

    static func kcalValues(_ lower: String) -> [Double] {
        numbers(in: lower, followedBy: "kcal")
    }

    /// Gram amounts in a row, skipping percentages of the reference intake.
    static func gramValues(_ lower: String) -> [Double] {
        let pattern = #"(<\s*)?(\d+(?:[.,]\d+)?)\s*(g\b|%|mg\b)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(lower.startIndex..., in: lower)
        var values: [Double] = []
        for match in regex.matches(in: lower, range: range) {
            let unit = Range(match.range(at: 3), in: lower).map { String(lower[$0]) }
            if unit == "%" || unit == "mg" { continue }
            guard let numberRange = Range(match.range(at: 2), in: lower),
                  let value = NumberInput.parse(String(lower[numberRange]))
            else { continue }
            values.append(value)
        }
        return values
    }

    static func numbers(in lower: String, followedBy unit: String) -> [Double] {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*"# + NSRegularExpression.escapedPattern(for: unit)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(lower.startIndex..., in: lower)
        return regex.matches(in: lower, range: range).compactMap { match in
            Range(match.range(at: 1), in: lower).flatMap { NumberInput.parse(String(lower[$0])) }
        }
    }

    /// "per 30g serving", "per serving (30g)", "30g serving", "per 1/2 pack (150g)".
    static func parseServingSize(_ lower: String) -> Double? {
        guard lower.contains("serving") || lower.contains("portion") || lower.contains("pack")
            || (lower.contains("per") && !lower.contains("100")) else { return nil }
        for value in numbers(in: lower, followedBy: "g") + numbers(in: lower, followedBy: "ml") where value != 100 && value > 0 {
            return value
        }
        return nil
    }
}
