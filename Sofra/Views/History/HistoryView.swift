//
//  HistoryView.swift
//  Sofra — month-grouped, navigable day history.
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @Query(sort: \QuickAddItem.sortOrder)
    private var quickItems: [QuickAddItem]

    @Query private var quickCounts: [QuickAddCount]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000

    private var monthSections: [HistoryMonthSection] {
        HistoryDaySummaryBuilder.monthSections(
            scans: scanEntries,
            items: quickItems,
            counts: quickCounts
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPage.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Layout.Spacing.xl) {
                        Text("Geçmiş")
                            .font(.sofraTitle)
                            .foregroundStyle(Color.textPrimary)

                        SevenDaySummaryView(embedded: true)

                        allDaysSection

                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.top, Layout.Spacing.md)
                }
            }
            .navigationDestination(for: Date.self) { date in
                DayDetailView(date: date)
            }
        }
    }

    @ViewBuilder
    private var allDaysSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("TÜM GÜNLER")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            if monthSections.isEmpty {
                emptyState
            } else {
                ForEach(monthSections) { section in
                    VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                        Text(monthTitle(section.month))
                            .font(.sofraEyebrow)
                            .tracking(1.2)
                            .foregroundStyle(Color.textMuted)

                        VStack(spacing: 0) {
                            ForEach(Array(section.days.enumerated()), id: \.element.id) { index, day in
                                NavigationLink(value: day.date) {
                                    dayRow(day)
                                }
                                .buttonStyle(.plain)

                                if index < section.days.count - 1 {
                                    Divider()
                                        .overlay(Color.borderHairline)
                                        .padding(.leading, Layout.Spacing.lg)
                                }
                            }
                        }
                        .background(
                            Color.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Layout.Radius.card)
                        )
                        .raisedSurface(cornerRadius: Layout.Radius.card)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: HistoryDaySummary) -> some View {
        HStack(spacing: Layout.Spacing.md) {
            Circle()
                .fill(day.calories <= calorieTarget ? Color.accentFill : Color.textMuted)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(dayName(day.date))
                    .font(.sofraBody)
                    .foregroundStyle(Color.textPrimary)
                Text(shortDate(day.date))
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(day.calories.rounded())) kcal")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.textPrimary)
                Text("\(day.mealCount) \(String(localized: "öğün"))")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textMuted)
        }
        .padding(Layout.Spacing.lg)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: Layout.Spacing.sm) {
            SofraIconView(icon: .tabak, size: 36)
                .foregroundStyle(Color.textMuted)
            Text("Henüz kayıtlı gün yok")
                .font(.sofraBody)
                .foregroundStyle(Color.textSecondary)
            Text("Öğün ekledikçe geçmişin burada görünecek.")
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
    }

    private func monthTitle(_ date: Date) -> String {
        Self.monthFormatter.string(from: date).capitalized(with: .autoupdatingCurrent)
    }

    private func dayName(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Bugün") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Dün") }
        return Self.dayFormatter.string(from: date).capitalized(with: .autoupdatingCurrent)
    }

    private func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()
}

struct HistoryDaySummary: Identifiable {
    let date: Date
    var calories: Double = 0
    var mealCount: Int = 0
    var quickAddTally: Int = 0

    var id: Date { date }
}

struct HistoryMonthSection: Identifiable {
    let month: Date
    let days: [HistoryDaySummary]

    var id: Date { month }
}

enum HistoryDaySummaryBuilder {
    static func monthSections(
        scans: [ScanEntry],
        items: [QuickAddItem],
        counts: [QuickAddCount],
        calendar: Calendar = .current
    ) -> [HistoryMonthSection] {
        let caloriesByItem = Dictionary(
            items.map { ($0.id, $0.caloriesPerUnit) },
            uniquingKeysWith: { first, _ in first }
        )
        var days: [Date: HistoryDaySummary] = [:]

        for scan in scans {
            let date = calendar.startOfDay(for: scan.timestamp)
            var summary = days[date] ?? HistoryDaySummary(date: date)
            summary.mealCount += 1
            summary.calories += scan.itemsOrEmpty.reduce(0) { $0 + $1.calories }
            days[date] = summary
        }

        for count in counts where count.count > 0 {
            let date = calendar.startOfDay(for: count.date)
            var summary = days[date] ?? HistoryDaySummary(date: date)
            summary.quickAddTally += count.count
            summary.calories += Double(count.count) * (caloriesByItem[count.itemID] ?? 0)
            days[date] = summary
        }

        let grouped = Dictionary(grouping: days.values) { summary in
            let components = calendar.dateComponents([.year, .month], from: summary.date)
            return calendar.date(from: components) ?? summary.date
        }

        return grouped
            .map { month, summaries in
                HistoryMonthSection(month: month, days: summaries.sorted { $0.date > $1.date })
            }
            .sorted { $0.month > $1.month }
    }
}
