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

/// Lightweight, precomputed daily summary for the home screen widget.
/// Pure Foundation — no SwiftData, SwiftUI, or WidgetKit imports.
struct WidgetDailySummary: Codable, Equatable {

    // MARK: - Raw values (set by main app)

    /// Total calories consumed today (sum of all LoggedItem.calories across today's scans).
    var calories: Double

    /// Daily calorie target from @AppStorage("sofra.dailyCalorieTarget") — default 2000.
    var target: Double

    /// Today's total protein (grams).
    var protein: Double

    /// Today's total carbs (grams).
    var carbs: Double

    /// Today's total fat (grams).
    var fat: Double

    /// Today's bread slice count from DailyQuickCounter.
    var breadSlices: Int

    /// Today's tea glass count from DailyQuickCounter.
    var teaGlasses: Int

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
        breadSlices: Int = 0,
        teaGlasses: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.calories = calories
        self.target = target
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.breadSlices = breadSlices
        self.teaGlasses = teaGlasses
        self.lastUpdated = lastUpdated

        // Precompute derived values
        self.progress = min(calories / max(target, 1), 1.0)
        self.remaining = max(target - calories, 0)
    }

    /// Fallback for first launch or when no data has been written yet.
    static let empty = WidgetDailySummary()
}
