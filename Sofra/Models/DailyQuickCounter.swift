//
//  DailyQuickCounter.swift
//  Sofra — quick-add counters (customizable) + their per-day tallies.
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
/// `caloriesPerUnit` is optional (0 = a pure tally that doesn't touch calories);
/// when > 0, each unit contributes to the day's calorie total and the ring.
@Model
final class QuickAddItem {
    var id: UUID = UUID()
    var name: String = ""
    var unit: String = ""
    /// SofraIcon rawValue (e.g. "ekmekDilimi").
    var iconName: String = "tabak"
    var caloriesPerUnit: Double = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String = "",
         unit: String = "",
         iconName: String = "tabak",
         caloriesPerUnit: Double = 0,
         sortOrder: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.iconName = iconName
        self.caloriesPerUnit = caloriesPerUnit
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Resolved icon (falls back to the plate icon for unknown names).
    var icon: SofraIcon { SofraIcon(rawValue: iconName) ?? .tabak }
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

// MARK: - Seeding

enum QuickAddSeed {
    /// Inserts the default Ekmek + Çay counters the first time the app runs
    /// (preserving v1 behaviour), only if no items exist yet.
    static func seedDefaultsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<QuickAddItem>())) ?? 0
        guard existing == 0 else { return }
        context.insert(QuickAddItem(name: "Ekmek", unit: "dilim",
                                    iconName: SofraIcon.ekmekDilimi.rawValue, sortOrder: 0))
        context.insert(QuickAddItem(name: "Çay", unit: "bardak",
                                    iconName: SofraIcon.cayBardagi.rawValue, sortOrder: 1))
        try? context.save()
    }
}
