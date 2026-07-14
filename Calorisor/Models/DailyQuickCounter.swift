//
//  DailyQuickCounter.swift
//  Calorisor — quick-add counters (customizable) + their per-day tallies.
//
//  v2: the hardcoded bread/tea counter (`DailyQuickCounter`) is replaced by
//  user-defined `QuickAddItem`s (name/unit/icon/optional calories) whose daily
//  tallies live in `QuickAddCount` rows. `DailyQuickCounter` is kept in the
//  schema for backward store compatibility but is no longer written.
//
//  All dates are normalized to the start of the day by the caller. No unique
//  constraints (CloudKit forbids them); the app fetches-or-creates per day.
//

import Foundation
import SwiftData

// MARK: - Legacy (kept only for store/schema compatibility — not written anymore)

@Model
final class DailyQuickCounter {
    var date: Date = Date()          // start-of-day
    var breadSlices: Int = 0         // ekmek dilimi
    var teaGlasses: Int = 0          // çay bardağı

    init(date: Date = Date(), breadSlices: Int = 0, teaGlasses: Int = 0) {
        self.date = date
        self.breadSlices = breadSlices
        self.teaGlasses = teaGlasses
    }
}

// MARK: - Customizable quick-add

/// A user-defined quick-add counter (e.g. "Ekmek · dilim", "Su · bardak").
/// Per-unit nutrition is optional (all 0 = a pure tally that doesn't touch the
/// totals); when set, each tallied unit contributes to the day's calories and
/// macros (ring + macro cards). New macro fields default to 0, so the schema
/// change is additive/CloudKit-safe for stores created before this version.
@Model
final class QuickAddItem {
    var id: UUID = UUID()
    var name: String = ""
    var unit: String = ""
    /// CalorisorIcon rawValue (e.g. "ekmekDilimi").
    var iconName: String = "tabak"
    var caloriesPerUnit: Double = 0
    var proteinPerUnit: Double = 0
    var carbsPerUnit: Double = 0
    var fatPerUnit: Double = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String = "",
         unit: String = "",
         iconName: String = "tabak",
         caloriesPerUnit: Double = 0,
         proteinPerUnit: Double = 0,
         carbsPerUnit: Double = 0,
         fatPerUnit: Double = 0,
         sortOrder: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.iconName = iconName
        self.caloriesPerUnit = caloriesPerUnit
        self.proteinPerUnit = proteinPerUnit
        self.carbsPerUnit = carbsPerUnit
        self.fatPerUnit = fatPerUnit
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Resolved icon (falls back to the plate icon for unknown names).
    var icon: CalorisorIcon { CalorisorIcon(rawValue: iconName) ?? .tabak }
}

/// One day's tally for a given `QuickAddItem` (linked by `itemID`, no relationship
/// so CloudKit mirroring stays simple). Fetched-or-created per (item, day).
@Model
final class QuickAddCount {
    var itemID: UUID = UUID()
    var date: Date = Date()   // start-of-day
    var count: Int = 0

    init(itemID: UUID = UUID(), date: Date = Date(), count: Int = 0) {
        self.itemID = itemID
        self.date = date
        self.count = count
    }
}

// MARK: - Templates

/// A ready-made quick-add with real per-unit nutrition for common Turkish
/// items. Used both to seed the defaults and to pre-fill the editor when the
/// user adds a new counter. Values are per single unit and deliberately
/// approximate (household portions, not lab-precise).
struct QuickAddTemplate: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let icon: CalorisorIcon
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum QuickAddTemplates {
    static let turkish: [QuickAddTemplate] = [
        .init(name: "Ekmek",        unit: "dilim",  icon: .ekmekDilimi, calories: 80,  protein: 2.7, carbs: 15,  fat: 1),
        .init(name: "Çay",          unit: "bardak", icon: .cayBardagi,  calories: 2,   protein: 0,   carbs: 0.5, fat: 0),
        .init(name: "Türk kahvesi", unit: "fincan", icon: .cayBardagi,  calories: 5,   protein: 0.3, carbs: 1,   fat: 0),
        .init(name: "Su",           unit: "bardak", icon: .cayBardagi,  calories: 0,   protein: 0,   carbs: 0,   fat: 0),
        .init(name: "Şeker",        unit: "küp",    icon: .kasik,       calories: 20,  protein: 0,   carbs: 5,   fat: 0),
        .init(name: "Ayran",        unit: "bardak", icon: .cayBardagi,  calories: 60,  protein: 3,   carbs: 5,   fat: 3),
        .init(name: "Simit",        unit: "adet",   icon: .ekmekDilimi, calories: 270, protein: 8,   carbs: 50,  fat: 4),
        .init(name: "Yumurta",      unit: "adet",   icon: .tabak,       calories: 70,  protein: 6,   carbs: 0.5, fat: 5),
        .init(name: "Peynir",       unit: "dilim",  icon: .ekmekDilimi, calories: 80,  protein: 5,   carbs: 1,   fat: 6),
        .init(name: "Zeytin",       unit: "adet",   icon: .kase,        calories: 5,   protein: 0,   carbs: 0,   fat: 0.5),
        .init(name: "Muz",          unit: "adet",   icon: .tabak,       calories: 100, protein: 1,   carbs: 27,  fat: 0),
        .init(name: "Elma",         unit: "adet",   icon: .tabak,       calories: 80,  protein: 0.5, carbs: 21,  fat: 0),
    ]

    static let english: [QuickAddTemplate] = [
        .init(name: "Bread",        unit: "slice", icon: .ekmekDilimi, calories: 80,  protein: 2.7, carbs: 15,  fat: 1),
        .init(name: "Coffee",       unit: "cup",   icon: .cayBardagi,  calories: 5,   protein: 0.3, carbs: 1,   fat: 0),
        .init(name: "Water",        unit: "glass", icon: .cayBardagi,  calories: 0,   protein: 0,   carbs: 0,   fat: 0),
        .init(name: "Egg",          unit: "piece", icon: .tabak,       calories: 70,  protein: 6,   carbs: 0.5, fat: 5),
        .init(name: "Banana",       unit: "piece", icon: .tabak,       calories: 100, protein: 1,   carbs: 27,  fat: 0),
        .init(name: "Apple",        unit: "piece", icon: .tabak,       calories: 80,  protein: 0.5, carbs: 21,  fat: 0),
        .init(name: "Cheese",       unit: "slice", icon: .ekmekDilimi, calories: 80,  protein: 5,   carbs: 1,   fat: 6),
        .init(name: "Yogurt",       unit: "bowl",  icon: .kase,        calories: 100, protein: 6,   carbs: 12,  fat: 3),
        .init(name: "Mixed Nuts",   unit: "handful", icon: .kase,      calories: 170, protein: 5,   carbs: 5,   fat: 15),
        .init(name: "Milk",         unit: "glass", icon: .cayBardagi,  calories: 120, protein: 8,   carbs: 12,  fat: 2.5),
        .init(name: "Orange Juice", unit: "glass", icon: .cayBardagi,  calories: 110, protein: 1,   carbs: 25,  fat: 0),
        .init(name: "Rice",         unit: "cup",   icon: .tabak,       calories: 200, protein: 4,   carbs: 44,  fat: 0.5),
    ]

    /// Returns the template set for the user's effective language.
    static var all: [QuickAddTemplate] {
        switch AppLanguage.current {
        case .system:
            return Locale.current.identifier.hasPrefix("tr") ? turkish : english
        case .turkish:
            return turkish
        case .english:
            return english
        }
    }
}

// MARK: - Seeding

enum QuickAddSeed {
    /// Inserts the default Ekmek + Çay counters the first time the app runs,
    /// now with real per-unit nutrition, only if no items exist yet.
    static func seedDefaultsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<QuickAddItem>())) ?? 0
        guard existing == 0 else { return }
        for (index, template) in QuickAddTemplates.all.prefix(2).enumerated() {
            context.insert(QuickAddItem.make(from: template, sortOrder: index))
        }
        try? context.save()
    }

    /// Repairs `QuickAddItem` rows created before per-unit nutrition fields
    /// carried real values — an additive SwiftData schema change left them at
    /// the column default (0), and `seedDefaultsIfNeeded`'s `existing == 0`
    /// guard never revisits a store that already has rows, so those stale
    /// zero-macro rows (e.g. a pre-migration "Ekmek") were never backfilled.
    ///
    /// Matches by exact name against `QuickAddTemplates.all` and only touches
    /// rows whose 4 macro fields are ALL currently 0 — never touches
    /// user-edited, user-renamed, or custom items. Safe to call every launch:
    /// a legitimately-all-zero template (e.g. "Su") just rewrites 0 → 0.
    static func backfillMissingNutrition(_ context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<QuickAddItem>()), !items.isEmpty else { return }
        let templatesByName = Dictionary(
            (QuickAddTemplates.turkish + QuickAddTemplates.english).map { ($0.name, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        var didChange = false
        for item in items {
            guard let template = templatesByName[item.name] else { continue }
            let isZero = item.caloriesPerUnit == 0 && item.proteinPerUnit == 0
                && item.carbsPerUnit == 0 && item.fatPerUnit == 0
            guard isZero else { continue }

            item.caloriesPerUnit = template.calories
            item.proteinPerUnit = template.protein
            item.carbsPerUnit = template.carbs
            item.fatPerUnit = template.fat
            if item.iconName == CalorisorIcon.tabak.rawValue {
                item.iconName = template.icon.rawValue
            }
            didChange = true
        }
        if didChange { try? context.save() }
    }
}

extension QuickAddItem {
    /// Build a counter from a template. A static factory (not a convenience
    /// init) to sidestep any interaction with the @Model-generated initializer.
    static func make(from template: QuickAddTemplate, sortOrder: Int) -> QuickAddItem {
        QuickAddItem(
            name: template.name,
            unit: template.unit,
            iconName: template.icon.rawValue,
            caloriesPerUnit: template.calories,
            proteinPerUnit: template.protein,
            carbsPerUnit: template.carbs,
            fatPerUnit: template.fat,
            sortOrder: sortOrder
        )
    }
}
