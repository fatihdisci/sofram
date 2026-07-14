import Foundation

enum HealthKitWeightTrendBuilder {
    /// Keeps the last reading for each calendar day and returns chronological
    /// points for a stable, readable trend chart.
    static func dailyLatest(
        from points: [HealthKitWeightPoint],
        calendar: Calendar = .current
    ) -> [HealthKitWeightPoint] {
        let latestByDay = Dictionary(grouping: points) { point in
            calendar.startOfDay(for: point.date)
        }.compactMapValues { dayPoints in
            dayPoints.max { $0.date < $1.date }
        }

        return latestByDay.values.sorted { $0.date < $1.date }
    }
}
