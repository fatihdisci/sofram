//
//  SevenDaySummaryView.swift
//  Sofra — trailing 7-day calories + bread/tea summary.
//
//  Presented as a sheet from the daily view. Compact list with
//  Geist Mono for numbers, warm palette consistent with design tokens.
//

import SwiftUI
import SwiftData

struct SevenDaySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyQuickCounter.date, order: .reverse)
    private var counters: [DailyQuickCounter]

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    /// Build day summaries from the last 7 days.
    private var daySummaries: [DaySummary] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [DaySummary] = []
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayEnd = cal.date(byAdding: .day, value: 1, to: date) ?? date

            // Calories from scan entries on this day
            let dayScans = scanEntries.filter { entry in
                entry.timestamp >= date && entry.timestamp < dayEnd
            }
            let calories = dayScans.reduce(0.0) { total, scan in
                total + (scan.itemsOrEmpty).reduce(0.0) { $0 + $1.calories }
            }

            // Bread/tea from quick counter for this day
            let dayCounter = counters.first(where: { counter in
                counter.date >= date && counter.date < dayEnd
            })

            result.append(DaySummary(
                date: date,
                calories: calories,
                breadSlices: dayCounter?.breadSlices ?? 0,
                teaGlasses: dayCounter?.teaGlasses ?? 0
            ))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPage.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: Layout.Spacing.sm) {
                        // Day column
                        Text("Gün")
                            .frame(width: 70, alignment: .leading)
                        // Calorie column
                        Text("Kalori")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        // Bread/tea column
                        HStack(spacing: Layout.Spacing.sm) {
                            SofraIconView(icon: .ekmekDilimi, size: 14)
                                .foregroundStyle(Color.textMuted)
                            Text("/")
                                .font(.sofraCaption)
                                .foregroundStyle(Color.textMuted)
                            SofraIconView(icon: .cayBardagi, size: 14)
                                .foregroundStyle(Color.textMuted)
                        }
                        .frame(width: 50)
                    }
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.sm)

                    Divider()
                        .overlay(Color.borderHairline)

                    // Day rows
                    List {
                        ForEach(daySummaries, id: \.date) { day in
                            HStack(spacing: Layout.Spacing.sm) {
                                Text(dayLabel(for: day.date))
                                    .frame(width: 70, alignment: .leading)

                                Text("\(Int(day.calories)) kcal")
                                    .font(.sofraNumericSmall)
                                    .foregroundStyle(Color.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                HStack(spacing: Layout.Spacing.sm) {
                                    Text("\(day.breadSlices)")
                                        .font(.sofraNumericSmall)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 18, alignment: .trailing)
                                    Text("\(day.teaGlasses)")
                                        .font(.sofraNumericSmall)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 18, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, Layout.Spacing.xs)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("7 Günlük Özet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(Color.accentText)
                }
            }
        }
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(3).capitalized
    }
}

struct DaySummary {
    let date: Date
    let calories: Double
    let breadSlices: Int
    let teaGlasses: Int
}
