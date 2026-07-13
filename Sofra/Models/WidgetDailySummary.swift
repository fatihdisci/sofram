//
//  WidgetDailySummary.swift
//  Sofra — precomputed daily summary shared between main app and widget extension.
//
//  This is the data contract: the main app computes today's totals from SwiftData
//  and writes a Codable blob to shared App Group UserDefaults. The widget reads it
//  in its TimelineProvider without importing SwiftData or duplicating computation.
//
//  Included in both the Sofra (main app) and SofraWidgetExtension targets.
//

import Foundation

struct QuickAddSnapshot: Codable, Equatable {
    var name: String
    var unit: String
    var count: Int
    var iconName: String
}

/// Lightweight, precomputed daily summary for the home screen widget.
/// Pure Foundation — no SwiftData, SwiftUI, or WidgetKit imports.
struct WidgetDailySummary: Codable, Equatable {

    // MARK: - Raw values (set by main app)

    /// Total calories consumed today (sum of all LoggedItem.calories across today's scans).
    var calories: Double

    /// Daily calorie target from @AppStorage("calorisor.dailyCalorieTarget") — default 2000.
    var target: Double

    /// Today's total protein (grams).
    var protein: Double

    /// Today's total carbs (grams).
    var carbs: Double

    /// Today's total fat (grams).
    var fat: Double

    /// The two most-used quick-add counters for today.
    var topQuickAdds: [QuickAddSnapshot]

    /// Legacy fields remain optional so previously saved widget JSON decodes.
    var breadSlices: Int?
    var teaGlasses: Int?

    /// When this summary was written. Used for diagnostics; not displayed.
    var lastUpdated: Date

    // MARK: - Precomputed convenience (computed in main app, not in widget)

    /// Ring fill fraction: `min(calories / max(target, 1), 1.0)`.
    var progress: Double

    /// Remaining calories: `max(target - calories, 0)`.
    var remaining: Double

    // MARK: - Initializer

    init(
        calories: Double = 0,
        target: Double = 2000,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        topQuickAdds: [QuickAddSnapshot] = [],
        breadSlices: Int? = nil,
        teaGlasses: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.calories = calories
        self.target = target
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.topQuickAdds = topQuickAdds
        self.breadSlices = breadSlices
        self.teaGlasses = teaGlasses
        self.lastUpdated = lastUpdated

        // Precompute derived values
        self.progress = min(calories / max(target, 1), 1.0)
        self.remaining = max(target - calories, 0)
    }

    /// Fallback for first launch or when no data has been written yet.
    static let empty = WidgetDailySummary()

    private enum CodingKeys: String, CodingKey {
        case calories, target, protein, carbs, fat
        case topQuickAdds, breadSlices, teaGlasses
        case lastUpdated, progress, remaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        target = try container.decodeIfPresent(Double.self, forKey: .target) ?? 2000
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        topQuickAdds = try container.decodeIfPresent([QuickAddSnapshot].self, forKey: .topQuickAdds) ?? []
        breadSlices = try container.decodeIfPresent(Int.self, forKey: .breadSlices)
        teaGlasses = try container.decodeIfPresent(Int.self, forKey: .teaGlasses)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? .now
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
            ?? min(calories / max(target, 1), 1)
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
            ?? max(target - calories, 0)
    }
}
