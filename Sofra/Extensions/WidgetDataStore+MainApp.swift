//
//  WidgetDataStore+MainApp.swift
//  Sofra — convenience method that queries SwiftData and writes the widget summary.
//
//  This file is compiled ONLY into the main Sofra target (not the widget extension).
//  It imports SwiftData + WidgetKit, which the widget target does not need.
//
//  Called from:
//    • ResultView.save()       — after logging a new scan
//    • DailyView.saveCounters() — after bread/tea counter change
//    • SofraApp.onChange(scenePhase) — catch-up on foreground
//

import Foundation
import SwiftData
import WidgetKit

extension WidgetDataStore {

    /// Queries today's ScanEntry + DailyQuickCounter from SwiftData, computes totals,
    /// builds a WidgetDailySummary, writes it to shared UserDefaults, and triggers
    /// an immediate widget timeline reload.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData ModelContext to query (from @Environment or container.mainContext).
    ///   - calorieTarget: Daily calorie target from UserDefaults key "sofra.dailyCalorieTarget" (default 2000).
    static func saveCurrentDaySummary(
        modelContext: ModelContext,
        calorieTarget: Double
    ) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }

        // Today's scans
        let scanDescriptor = FetchDescriptor<ScanEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allScans = (try? modelContext.fetch(scanDescriptor)) ?? []
        let todayScans = allScans.filter { $0.timestamp >= today && $0.timestamp < tomorrow }

        // Sum macros
        let calories = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.calories }
        }
        let protein = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.protein }
        }
        let carbs = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.carbs }
        }
        let fat = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.fat }
        }

        // Today's quick counter
        let counterDescriptor = FetchDescriptor<DailyQuickCounter>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let counters = (try? modelContext.fetch(counterDescriptor)) ?? []
        let todayCounter = counters.first { $0.date >= today && $0.date < tomorrow }
        let breadSlices = todayCounter?.breadSlices ?? 0
        let teaGlasses = todayCounter?.teaGlasses ?? 0

        // Build and save
        let target = calorieTarget > 0 ? calorieTarget : 2000
        let summary = WidgetDailySummary(
            calories: calories,
            target: target,
            protein: protein,
            carbs: carbs,
            fat: fat,
            breadSlices: breadSlices,
            teaGlasses: teaGlasses,
            lastUpdated: Date()
        )
        save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
