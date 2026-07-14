import Foundation

struct WeeklySummary {
    let days: [DaySummary]
    let previousDays: [DaySummary]
    let dailyCalorieTarget: Double
    let loggedDayCount: Int
    let averageCalories: Double
    let averageProtein: Double
    let targetMetDayCount: Int
    let highestCalorieDay: DaySummary?
    let lowestCalorieDay: DaySummary?
    let nightMealCount: Int
    let previousAverageCalories: Double?
    let calorieChangeFromPreviousWeek: Double?
    let calorieChangePercentFromPreviousWeek: Double?
    let activeEnergyKcal: Double?
    let weightChangeKg: Double?
}

enum WeeklySummaryBuilder {
    static func build(
        scans: [ScanEntry],
        items: [QuickAddItem],
        counts: [QuickAddCount],
        dailyCalorieTarget: Double,
        now: Date = .now,
        activeEnergyKcal: Double? = nil,
        weightChangeKg: Double? = nil,
        calendar: Calendar = .current
    ) -> WeeklySummary {
        let days = DaySummaryBuilder.trailingDays(
            endingAt: now,
            count: 7,
            scans: scans,
            items: items,
            counts: counts,
            calendar: calendar
        )
        let previousEnd = calendar.date(
            byAdding: .day,
            value: -7,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let previousDays = DaySummaryBuilder.trailingDays(
            endingAt: previousEnd,
            count: 7,
            scans: scans,
            items: items,
            counts: counts,
            calendar: calendar
        )

        let loggedDays = days.filter(\.hasActivity)
        let calorieDays = days.filter { $0.calories > 0 }
        let previousCalorieDays = previousDays.filter { $0.calories > 0 }
        let averageCalories = average(calorieDays.map(\.calories))
        let averageProtein = average(loggedDays.map(\.protein))
        let previousAverageCalories = averageOrNil(previousCalorieDays.map(\.calories))
        let change = previousAverageCalories.map { averageCalories - $0 }
        let changePercent: Double?
        if let previous = previousAverageCalories, previous > 0 {
            changePercent = ((averageCalories - previous) / previous) * 100
        } else {
            changePercent = nil
        }

        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let nightMealCount = scans.filter { scan in
            guard scan.timestamp >= start, scan.timestamp <= now else { return false }
            guard scan.itemsOrEmpty.contains(where: { $0.calories > 0 }) else { return false }
            let hour = calendar.component(.hour, from: scan.timestamp)
            return hour >= 22 || hour < 5
        }.count

        return WeeklySummary(
            days: days,
            previousDays: previousDays,
            dailyCalorieTarget: dailyCalorieTarget,
            loggedDayCount: loggedDays.count,
            averageCalories: averageCalories,
            averageProtein: averageProtein,
            targetMetDayCount: calorieDays.filter { $0.calories <= dailyCalorieTarget }.count,
            highestCalorieDay: calorieDays.max { $0.calories < $1.calories },
            lowestCalorieDay: calorieDays.min { $0.calories < $1.calories },
            nightMealCount: nightMealCount,
            previousAverageCalories: previousAverageCalories,
            calorieChangeFromPreviousWeek: change,
            calorieChangePercentFromPreviousWeek: changePercent,
            activeEnergyKcal: activeEnergyKcal,
            weightChangeKg: weightChangeKg
        )
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageOrNil(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : average(values)
    }
}
