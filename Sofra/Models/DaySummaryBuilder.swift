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
    let protein: Double
    let carbs: Double
    let fat: Double
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
        let nutritionPerItem = Dictionary(
            items.map {
                ($0.id, ($0.caloriesPerUnit, $0.proteinPerUnit, $0.carbsPerUnit, $0.fatPerUnit))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date

            let dayScans = scans.filter { $0.timestamp >= date && $0.timestamp < dayEnd }
            let scanCalories = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.calories }
            }
            let scanProtein = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.protein }
            }
            let scanCarbs = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.carbs }
            }
            let scanFat = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.fat }
            }

            let dayCounts = counts.filter { $0.date >= date && $0.date < dayEnd }
            let quickNutrition = dayCounts.reduce(into: (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0)) { total, count in
                guard let values = nutritionPerItem[count.itemID] else { return }
                let quantity = Double(count.count)
                total.calories += quantity * values.0
                total.protein += quantity * values.1
                total.carbs += quantity * values.2
                total.fat += quantity * values.3
            }
            let tally = dayCounts.reduce(0) { $0 + $1.count }

            return DaySummary(
                date: date,
                calories: scanCalories + quickNutrition.calories,
                protein: scanProtein + quickNutrition.protein,
                carbs: scanCarbs + quickNutrition.carbs,
                fat: scanFat + quickNutrition.fat,
                quickAddTally: tally
            )
        }
    }
}
