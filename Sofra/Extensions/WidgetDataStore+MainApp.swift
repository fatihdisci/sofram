//
//  WidgetDataStore+MainApp.swift
//  Sofra — convenience method that queries SwiftData and writes the widget summary.
//
//  This file is compiled ONLY into the main Sofra target (not the widget extension).
//  It imports SwiftData + WidgetKit, which the widget target does not need.
//
//  Called from:
//    • ResultView.save()        — after logging a new scan
//    • QuickCounterView         — after a quick-add tally change
//    • SofraApp.onChange(scenePhase) — catch-up on foreground
//

import Foundation
import SwiftData
import WidgetKit

extension WidgetDataStore {

    /// Queries today's ScanEntry + quick-add tallies from SwiftData, computes totals,
    /// builds a WidgetDailySummary, writes it to shared UserDefaults, and triggers
    /// an immediate widget timeline reload.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData ModelContext to query (from @Environment or container.mainContext).
    ///   - calorieTarget: Daily calorie target from UserDefaults key "calorisor.dailyCalorieTarget" (default 2000).
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

        // Sum macros from scans
        let scanCalories = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.calories }
        }
        let scanProtein = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.protein }
        }
        let scanCarbs = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.carbs }
        }
        let scanFat = todayScans.reduce(0.0) { total, scan in
            total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.fat }
        }

        // Customizable quick-add: fold each calorie/macro-bearing item into the
        // totals, and surface the first two items' tallies in the legacy widget
        // slots (so the default Ekmek/Çay setup keeps rendering as before).
        let itemDescriptor = FetchDescriptor<QuickAddItem>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let items = (try? modelContext.fetch(itemDescriptor)) ?? []
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allCounts = (try? modelContext.fetch(FetchDescriptor<QuickAddCount>())) ?? []
        let todayCounts = allCounts.filter { $0.date >= today && $0.date < tomorrow }
        let talliesByItemID = Dictionary(grouping: todayCounts, by: \.itemID)
            .mapValues { counts in counts.reduce(0) { $0 + $1.count } }

        func quickSum(_ perUnit: (QuickAddItem) -> Double) -> Double {
            todayCounts.reduce(0.0) { sum, c in
                guard let item = itemsByID[c.itemID] else { return sum }
                return sum + Double(c.count) * perUnit(item)
            }
        }
        func todayTally(for item: QuickAddItem) -> Int {
            talliesByItemID[item.id] ?? 0
        }
        let breadSlices = items.count > 0 ? todayTally(for: items[0]) : 0
        let teaGlasses  = items.count > 1 ? todayTally(for: items[1]) : 0
        let topQuickAdds = talliesByItemID
            .compactMap { itemID, count -> (QuickAddItem, Int)? in
                guard count > 0, let item = itemsByID[itemID] else { return nil }
                return (item, count)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.sortOrder < rhs.0.sortOrder : lhs.1 > rhs.1
            }
            .prefix(2)
            .map { item, count in
                QuickAddSnapshot(
                    name: item.name,
                    unit: item.unit,
                    count: count,
                    iconName: item.iconName
                )
            }

        // Build and save
        let target = calorieTarget > 0 ? calorieTarget : 2000
        let summary = WidgetDailySummary(
            calories: scanCalories + quickSum { $0.caloriesPerUnit },
            target: target,
            protein: scanProtein + quickSum { $0.proteinPerUnit },
            carbs: scanCarbs + quickSum { $0.carbsPerUnit },
            fat: scanFat + quickSum { $0.fatPerUnit },
            topQuickAdds: topQuickAdds,
            breadSlices: breadSlices,
            teaGlasses: teaGlasses,
            lastUpdated: Date()
        )
        save(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
