import CryptoKit
import Foundation
import SwiftData

struct FrequentMealItem: Equatable, Identifiable {
    let id: UUID
    let name: String
    let nameEn: String
    let portionUnit: PortionUnit
    let quantity: Double
    let estimatedGrams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let confidence: Double
    let note: String?
    let valueSource: String?
}

struct FrequentMeal: Identifiable, Equatable {
    let id: String
    let name: String
    let items: [FrequentMealItem]
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let usageCount: Int
    let lastUsed: Date

    var widgetSnapshot: FrequentMealSnapshot {
        FrequentMealSnapshot(
            id: id,
            name: name,
            totalCalories: totalCalories,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            lastUsed: lastUsed,
            items: items.map {
                FrequentMealItemSnapshot(
                    name: $0.name,
                    nameEn: $0.nameEn,
                    portionUnit: $0.portionUnit.rawValue,
                    quantity: $0.quantity,
                    estimatedGrams: $0.estimatedGrams,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    confidence: $0.confidence,
                    note: $0.note,
                    valueSource: $0.valueSource
                )
            }
        )
    }
}

enum FrequentMealsBuilder {
    static let lookbackDays = 30
    static let maximumResults = 5

    static func build(
        scans: [ScanEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [FrequentMeal] {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        struct Group {
            var items: [FrequentMealItem]
            var count: Int
            var lastUsed: Date
            var name: String
        }

        var groups: [String: Group] = [:]
        for scan in scans where scan.timestamp >= cutoff && scan.timestamp <= now && !scan.itemsOrEmpty.isEmpty {
            let items = scan.itemsOrEmpty.map { item in
                FrequentMealItem(
                    id: UUID(),
                    name: item.name,
                    nameEn: item.nameEn,
                    portionUnit: item.portionUnit,
                    quantity: item.quantity,
                    estimatedGrams: item.estimatedGrams,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    confidence: item.confidence,
                    note: item.note,
                    valueSource: item.valueSource
                )
            }
            let identity = mealIdentity(items: items)
            let mealName = items.map { $0.name }.joined(separator: " + ")
            if var group = groups[identity] {
                group.count += 1
                group.lastUsed = max(group.lastUsed, scan.timestamp)
                groups[identity] = group
            } else {
                groups[identity] = Group(items: items, count: 1, lastUsed: scan.timestamp, name: mealName)
            }
        }

        var meals: [FrequentMeal] = []
        for (id, group) in groups {
            let totalCalories = group.items.reduce(0) { $0 + $1.calories }
            let totalProtein = group.items.reduce(0) { $0 + $1.protein }
            let totalCarbs = group.items.reduce(0) { $0 + $1.carbs }
            let totalFat = group.items.reduce(0) { $0 + $1.fat }
            meals.append(FrequentMeal(
                id: id, name: group.name, items: group.items,
                totalCalories: totalCalories, totalProtein: totalProtein,
                totalCarbs: totalCarbs, totalFat: totalFat,
                usageCount: group.count, lastUsed: group.lastUsed
            ))
        }
        return meals.sorted {
            $0.usageCount == $1.usageCount ? $0.lastUsed > $1.lastUsed : $0.usageCount > $1.usageCount
        }
        .prefix(maximumResults)
        .map { $0 }
    }

    static func mealIdentity(items: [FrequentMealItem]) -> String {
        let canonical = items.map { item in
            let name = normalize(item.name)
            let unit = normalize(item.portionUnit.rawValue)
            let quantity = rounded(item.quantity)
            return name + "|" + unit + "|" + quantity
        }
        .sorted()
        .joined(separator: "||")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func meal(from snapshot: FrequentMealSnapshot) -> FrequentMeal {
        FrequentMeal(
            id: snapshot.id,
            name: snapshot.name,
            items: snapshot.items.map {
                FrequentMealItem(
                    id: UUID(), name: $0.name, nameEn: $0.nameEn,
                    portionUnit: PortionUnit(apiValue: $0.portionUnit),
                    quantity: $0.quantity, estimatedGrams: $0.estimatedGrams,
                    calories: $0.calories, protein: $0.protein, carbs: $0.carbs,
                    fat: $0.fat, confidence: $0.confidence, note: $0.note,
                    valueSource: $0.valueSource
                )
            },
            totalCalories: snapshot.totalCalories,
            totalProtein: snapshot.totalProtein,
            totalCarbs: snapshot.totalCarbs,
            totalFat: snapshot.totalFat,
            usageCount: 0,
            lastUsed: snapshot.lastUsed
        )
    }

    /// Creates a completely independent ScanEntry/LoggedItem graph. The source
    /// meal is a value snapshot; no relationship or persistent model is reused.
    @discardableResult
    static func deepCopy(
        _ meal: FrequentMeal,
        into context: ModelContext,
        timestamp: Date = .now
    ) -> ScanEntry {
        let entry = ScanEntry(timestamp: timestamp, source: .manual, rawAIResponse: "")
        entry.items = meal.items.map { item in
            LoggedItem(
                name: item.name,
                nameEn: item.nameEn,
                portionUnit: item.portionUnit,
                quantity: item.quantity,
                estimatedGrams: item.estimatedGrams,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                confidence: item.confidence,
                note: item.note,
                valueSource: item.valueSource
            )
        }
        context.insert(entry)
        return entry
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func rounded(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
