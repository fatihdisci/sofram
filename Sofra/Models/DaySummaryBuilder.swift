//
//  DaySummaryBuilder.swift
//  Sofra — shared per-day aggregation for the daily sparkline and the
//  7-day summary sheet (single source of truth for the day math).
//

import Foundation

struct DaySummary {
    let date: Date
    /// Total intake: scan calories + calorie-bearing quick-adds.
    let calories: Double
    /// Sum of all quick-add tallies for the day (any item, calorie-bearing or not).
    let quickAddTally: Int
}

enum DaySummaryBuilder {

    /// Aggregates the trailing 7 days (today first) from scan entries and the
    /// customizable quick-add items + their per-day counts.
    static func lastSevenDays(scans: [ScanEntry],
                              items: [QuickAddItem],
                              counts: [QuickAddCount],
                              calendar: Calendar = .current) -> [DaySummary] {
        let caloriesPerItem = Dictionary(items.map { ($0.id, $0.caloriesPerUnit) },
                                         uniquingKeysWith: { a, _ in a })
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date

            let dayScans = scans.filter { $0.timestamp >= date && $0.timestamp < dayEnd }
            let scanCalories = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.calories }
            }

            let dayCounts = counts.filter { $0.date >= date && $0.date < dayEnd }
            let quickCalories = dayCounts.reduce(0.0) { sum, c in
                sum + Double(c.count) * (caloriesPerItem[c.itemID] ?? 0)
            }
            let tally = dayCounts.reduce(0) { $0 + $1.count }

            return DaySummary(
                date: date,
                calories: scanCalories + quickCalories,
                quickAddTally: tally
            )
        }
    }
}
