import Foundation
import Testing
@testable import WaterTracker

struct NutritionTests {
    @Test func scalingAndTotals() {
        let toast = Nutrients(kcal: 80, protein: 3, carbs: 15, fat: 1)
        let two = toast.scaled(by: 2)
        #expect(two == Nutrients(kcal: 160, protein: 6, carbs: 30, fat: 2))
        #expect([toast, toast].total() == two)
    }

    @Test func caloriesFromMacros() {
        let n = Nutrients(kcal: 0, protein: 10, carbs: 20, fat: 5)
        #expect(n.kcalFromMacros == 165)
        #expect(n.hasMacros)
        #expect(!Nutrients.zero.hasMacros)
    }

    @Test func numberInput() {
        #expect(NumberInput.parse("12,5") == 12.5)
        #expect(NumberInput.parse(" 7 ") == 7)
        #expect(NumberInput.parse("") == nil)
        #expect(NumberInput.parse("-3") == nil)
        #expect(NumberInput.parse("abc") == nil)
    }

    @Test func recipePerServing() {
        let oats = Ingredient(name: "Oats", nutrients: Nutrients(kcal: 370, protein: 13, carbs: 60, fat: 7), isPer100g: true, amount: 200)
        let banana = Ingredient(name: "Banana", nutrients: Nutrients(kcal: 105, protein: 1, carbs: 27, fat: 0), isPer100g: false, amount: 2)
        #expect(Recipe.total([oats, banana]).kcal == 950)
        #expect(Recipe.perServing([oats, banana], servings: 4).kcal == 237.5)
        #expect(Recipe.perServing([], servings: 0) == .zero)
    }
}

struct LabelParserTests {
    private func line(_ text: String, x: Double, y: Double) -> TextLine {
        TextLine(text: text, minX: x, minY: y, height: 0.03)
    }

    /// A typical UK back-of-pack table, read as separate text boxes.
    @Test func ukTableInColumns() {
        let lines = [
            line("Typical values", x: 0.05, y: 0.10), line("Per 100g", x: 0.45, y: 0.10), line("Per 40g serving", x: 0.70, y: 0.10),
            line("Energy", x: 0.05, y: 0.15), line("1569kJ", x: 0.45, y: 0.15), line("628kJ", x: 0.70, y: 0.15),
            line("373kcal", x: 0.45, y: 0.19), line("149kcal", x: 0.70, y: 0.19),
            line("Fat", x: 0.05, y: 0.23), line("8.0g", x: 0.45, y: 0.23), line("3.2g", x: 0.70, y: 0.23),
            line("of which saturates", x: 0.05, y: 0.27), line("1.5g", x: 0.45, y: 0.27), line("0.6g", x: 0.70, y: 0.27),
            line("Carbohydrate", x: 0.05, y: 0.31), line("60g", x: 0.45, y: 0.31), line("24g", x: 0.70, y: 0.31),
            line("of which sugars", x: 0.05, y: 0.35), line("1.1g", x: 0.45, y: 0.35), line("<0.5g", x: 0.70, y: 0.35),
            line("Fibre", x: 0.05, y: 0.39), line("9.0g", x: 0.45, y: 0.39), line("3.6g", x: 0.70, y: 0.39),
            line("Protein", x: 0.05, y: 0.43), line("11g", x: 0.45, y: 0.43), line("4.4g", x: 0.70, y: 0.43),
            line("Salt", x: 0.05, y: 0.47), line("0.02g", x: 0.45, y: 0.47), line("0.01g", x: 0.70, y: 0.47),
        ]
        let facts = LabelParser.parse(lines.shuffled())
        #expect(facts.per100 == Nutrients(kcal: 373, protein: 11, carbs: 60, fat: 8))
        #expect(facts.perServing == Nutrients(kcal: 149, protein: 4.4, carbs: 24, fat: 3.2))
        #expect(facts.servingSize == 40)
    }

    @Test func singleLinesWithReferenceIntake() {
        let rows = [
            "Energy 1046kJ/250kcal 523kJ/125kcal 6%",
            "Fat 12,5g 6,3g 9%",
            "Carbohydrate 20g 10g 4%",
            "Protein 15g 7.5g 15%",
        ]
        let lines = rows.enumerated().map { line($1, x: 0.05, y: Double($0) * 0.05) }
        let facts = LabelParser.parse(lines)
        #expect(facts.per100 == Nutrients(kcal: 250, protein: 15, carbs: 20, fat: 12.5))
        #expect(facts.perServing?.kcal == 125)
    }

    @Test func energyOnlyInKilojoules() {
        let lines = [line("Energy 418kJ", x: 0, y: 0), line("Protein 5g", x: 0, y: 0.05)]
        #expect(LabelParser.parse(lines).per100?.kcal == 100)
    }

    @Test func nothingReadable() {
        #expect(LabelParser.parse([line("Ingredients: water, salt", x: 0, y: 0)]).isEmpty)
    }
}

struct OpenFoodFactsTests {
    @Test func parsesProduct() throws {
        let json = """
        {"code":"5000168001234","product":{"product_name":"Digestive Biscuits","brands":"McVitie's, Pladis",
        "serving_quantity":"14.7","nutriments":{"energy-kcal_100g":483,"proteins_100g":"7.1",
        "carbohydrates_100g":62.6,"fat_100g":21.3,"energy-kcal_serving":71}},"status":1}
        """
        let facts = try OpenFoodFacts.parse(Data(json.utf8))
        #expect(facts.name == "Digestive Biscuits (McVitie's)")
        #expect(facts.per100 == Nutrients(kcal: 483, protein: 7.1, carbs: 62.6, fat: 21.3))
        #expect(facts.perServing?.kcal == 71)
        #expect(facts.servingSize == 14.7)
    }

    @Test func kilojoulesOnly() throws {
        let json = #"{"product":{"product_name":"Squash","nutriments":{"energy_100g":41.84}}}"#
        #expect(try OpenFoodFacts.parse(Data(json.utf8)).per100?.kcal == 10)
    }

    @Test func missingProduct() {
        let json = #"{"status":0,"status_verbose":"product not found"}"#
        #expect(throws: OpenFoodFacts.LookupError.self) {
            try OpenFoodFacts.parse(Data(json.utf8))
        }
    }
}

struct ExerciseHistoryTests {
    private let monday = Date(timeIntervalSince1970: 1_700_000_000)
    private var thursday: Date { monday.addingTimeInterval(3 * 86_400) }
    private var nextMonday: Date { monday.addingTimeInterval(7 * 86_400) }

    private var records: [SetRecord] {
        [
            SetRecord(exercise: "Press banca", reps: 8, weightKg: 60, order: 0, sessionDate: monday),
            SetRecord(exercise: "Press banca", reps: 8, weightKg: 60, order: 1, sessionDate: monday),
            SetRecord(exercise: "Press Banca ", reps: 6, weightKg: 65, order: 1, sessionDate: thursday),
            SetRecord(exercise: "Press banca", reps: 8, weightKg: 62.5, order: 0, sessionDate: thursday),
            SetRecord(exercise: "Sentadilla", reps: 5, weightKg: 100, order: 0, sessionDate: thursday),
        ]
    }

    @Test func lastSessionIsMostRecentBeforeDate() {
        let last = ExerciseHistory.lastSession(of: "press banca", in: records, before: nextMonday)
        #expect(last.map(\.weightKg) == [62.5, 65])
        let earlier = ExerciseHistory.lastSession(of: "Press banca", in: records, before: thursday)
        #expect(earlier.count == 2 && earlier.allSatisfy { $0.weightKg == 60 })
        #expect(ExerciseHistory.lastSession(of: "Peso muerto", in: records, before: nextMonday).isEmpty)
    }

    @Test func oneRepMax() {
        #expect(ExerciseHistory.estimatedOneRepMax(weightKg: 100, reps: 1) == 100)
        #expect(ExerciseHistory.estimatedOneRepMax(weightKg: 60, reps: 10) == 80)
        #expect(ExerciseHistory.estimatedOneRepMax(weightKg: 60, reps: 0) == 0)
    }

    @Test func summaries() {
        let same = records.filter { $0.sessionDate == monday }
        #expect(ExerciseHistory.summary(same, unit: .kg) == "2 × 8 · 60 kg")
        let mixed = ExerciseHistory.lastSession(of: "Press banca", in: records, before: nextMonday)
        #expect(ExerciseHistory.summary(mixed, unit: .kg) == "8, 6 reps · 62.5–65 kg")
    }

    @Test func weightUnits() {
        #expect(abs(WeightUnit.lb.fromKilograms(100) - 220.462) < 0.001)
        #expect(abs(WeightUnit.lb.toKilograms(220.462262185) - 100) < 0.0001)
        #expect(WeightUnit.kg.fromKilograms(42) == 42)
    }
}
