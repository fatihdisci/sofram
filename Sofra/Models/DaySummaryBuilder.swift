//
//  DaySummaryBuilder.swift
//  Sofra — shared per-day aggregation for the daily sparkline and the
//  7-day summary sheet (single source of truth for the day math).
//

import Foundation

struct DaySummary {
    let date: Date
    let calories: Double
    let breadSlices: Int
    let teaGlasses: Int
}

enum DaySummaryBuilder {

    /// Aggregates the trailing 7 days (today first) from scan entries + quick counters.
    static func lastSevenDays(scans: [ScanEntry],
                              counters: [DailyQuickCounter],
                              calendar: Calendar = .current) -> [DaySummary] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date

            let dayScans = scans.filter { $0.timestamp >= date && $0.timestamp < dayEnd }
            let calories = dayScans.reduce(0.0) { total, scan in
                total + scan.itemsOrEmpty.reduce(0.0) { $0 + $1.calories }
            }

            let dayCounter = counters.first { $0.date >= date && $0.date < dayEnd }

            return DaySummary(
                date: date,
                calories: calories,
                breadSlices: dayCounter?.breadSlices ?? 0,
                teaGlasses: dayCounter?.teaGlasses ?? 0
            )
        }
    }
}
