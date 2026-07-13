//
//  SevenDaySummaryView.swift
//  Sofra — trailing 7-day calories + bread/tea summary.
//
//  Presented as a sheet from the daily view: header stats (average kcal,
//  total bread/tea), a 7-bar chart with the daily target line, and an
//  aligned day-by-day breakdown. Geist Mono for numbers, warm palette.
//
//  Tea counts above the daily threshold appear here as passive data only
//  (mikro-etkilesimler.md: no in-the-moment shaming).
//

import SwiftUI
import SwiftData

struct SevenDaySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    /// When true the view is hosted inside the Geçmiş tab (not a sheet): the
    /// close button and sheet presentation modifiers are dropped.
    var embedded: Bool = false

    @Query(sort: \QuickAddItem.sortOrder)
    private var quickItems: [QuickAddItem]

    @Query private var quickCounts: [QuickAddCount]

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000

    /// Trailing 7 days, today first.
    private var daySummaries: [DaySummary] {
        DaySummaryBuilder.lastSevenDays(scans: scanEntries, items: quickItems, counts: quickCounts)
    }

    private var loggedDays: [DaySummary] { daySummaries.filter { $0.calories > 0 } }

    private var averageCalories: Double {
        guard !loggedDays.isEmpty else { return 0 }
        return loggedDays.reduce(0) { $0 + $1.calories } / Double(loggedDays.count)
    }

    private var totalQuickAdds: Int { daySummaries.reduce(0) { $0 + $1.quickAddTally } }

    private func averageMacro(_ value: (DaySummary) -> Double) -> Double {
        guard !loggedDays.isEmpty else { return 0 }
        return loggedDays.reduce(0) { $0 + value($1) } / Double(loggedDays.count)
    }

    @ViewBuilder
    var body: some View {
        if embedded {
            embeddedContent
        } else {
            content
                .presentationDetents([.large])
                .presentationCornerRadius(24)
                .presentationBackground(Color.bgPage)
                .presentationDragIndicator(.visible)
        }
    }

    private var embeddedContent: some View {
        VStack(spacing: Layout.Spacing.lg) {
            statsRow

            if loggedDays.isEmpty {
                emptyState
            } else {
                chartCard
            }

            macroStatsRow
        }
    }

    private var content: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Layout.Spacing.lg) {
                        statsRow

                        if loggedDays.isEmpty {
                            emptyState
                        } else {
                            chartCard
                        }

                        macroStatsRow

                        dayRows
                    }
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.top, Layout.Spacing.md)
                    .padding(.bottom, Layout.Spacing.xxl)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("7 Günlük Özet")
                .font(.sofraHeading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if !embedded {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.surfaceRaised, in: Circle())
                }
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.lg)
        .padding(.bottom, Layout.Spacing.sm)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: Layout.Spacing.md) {
            StatCell(value: "\(Int(averageCalories))", caption: "ort. kcal / gün")
            StatCell(value: "\(loggedDays.count)", caption: "kayıtlı gün")
            StatCell(value: "\(totalQuickAdds)", caption: "hızlı ekleme")
        }
    }

    private var macroStatsRow: some View {
        HStack(spacing: Layout.Spacing.md) {
            StatCell(value: "\(Int(averageMacro(\.protein))) g", caption: "ort. protein / gün")
            StatCell(value: "\(Int(averageMacro(\.carbs))) g", caption: "ort. karb. / gün")
            StatCell(value: "\(Int(averageMacro(\.fat))) g", caption: "ort. yağ / gün")
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("Kalori")
                .font(.sofraCaption)
                .foregroundStyle(Color.textSecondary)

            WeekBarChart(summaries: daySummaries, target: calorieTarget)
                .frame(height: 160)

            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.textMuted)
                    .frame(width: 14, height: 1)
                Text("hedef · \(Int(calorieTarget)) kcal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer))
        .raisedSurface(cornerRadius: Layout.Radius.raisedContainer)
    }

    private var emptyState: some View {
        VStack(spacing: Layout.Spacing.md) {
            SofraIconView(icon: .tabak, size: 40)
                .foregroundStyle(Color.textMuted)
            Text("Henüz kayıtlı gün yok")
                .font(.sofraBody)
                .foregroundStyle(Color.textSecondary)
            Text("Öğün ekledikçe haftalık görünüm burada dolacak.")
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer))
    }

    // MARK: - Day rows

    private var dayRows: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: Layout.Spacing.sm) {
                Text("Gün")
                    .frame(width: 64, alignment: .leading)
                Spacer()
                Text("Kalori")
                    .frame(width: 90, alignment: .trailing)
                Text("Hızlı ekleme")
                    .frame(width: 88, alignment: .trailing)
            }
            .font(.sofraCaption)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, Layout.Spacing.lg)
            .padding(.vertical, Layout.Spacing.sm)

            ForEach(Array(daySummaries.enumerated()), id: \.element.date) { idx, day in
                HStack(spacing: Layout.Spacing.sm) {
                    Text(dayLabel(for: day.date))
                        .font(idx == 0 ? .sofraLabel : .sofraBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 64, alignment: .leading)
                    Spacer()
                    Text(day.calories > 0 ? "\(Int(day.calories)) kcal" : "—")
                        .font(.sofraNumericSmall)
                        .foregroundStyle(day.calories > 0 ? Color.textPrimary : Color.textMuted)
                        .frame(width: 90, alignment: .trailing)
                    Text(day.quickAddTally > 0 ? "\(day.quickAddTally)" : "—")
                        .font(.sofraNumericSmall)
                        .foregroundStyle(day.quickAddTally > 0 ? Color.textSecondary : Color.textMuted)
                        .frame(width: 88, alignment: .trailing)
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.vertical, Layout.Spacing.md)
                .background(
                    idx == 0 ? Color.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: Layout.Radius.control)
                )

                if idx < daySummaries.count - 1 {
                    Divider()
                        .overlay(Color.borderHairline)
                        .padding(.horizontal, Layout.Spacing.lg)
                }
            }
        }
        .padding(.vertical, Layout.Spacing.xs)
        .background(Color.bgPage)
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return SofraFormatters.turkishShortWeekday.string(from: date).prefix(3).capitalized
    }
}

// MARK: - Stat cell

private struct StatCell: View {
    let value: String
    let caption: String
    var icon: SofraIcon?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    SofraIconView(icon: icon, size: 16)
                        .foregroundStyle(Color.accentFill)
                }
                Text(value)
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Spacing.md)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }
}

// MARK: - Week bar chart

/// Seven vertical bars (oldest → newest) with a dashed target line.
/// Today's bar is full copper; other days are muted copper.
struct WeekBarChart: View {
    let summaries: [DaySummary]   // today first
    let target: Double

    var body: some View {
        let ordered = Array(summaries.reversed())
        let peak = max(ordered.map(\.calories).max() ?? 0, target) * 1.15

        GeometryReader { geo in
            let chartHeight = geo.size.height - 22  // reserve label strip

            ZStack(alignment: .bottom) {
                // Target line
                Path { p in
                    let y = chartHeight * (1 - target / peak)
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.textMuted.opacity(0.6))

                // Bars + day labels
                HStack(alignment: .bottom, spacing: Layout.Spacing.sm) {
                    ForEach(Array(ordered.enumerated()), id: \.offset) { idx, day in
                        let isToday = idx == ordered.count - 1
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(isToday
                                      ? AnyShapeStyle(LinearGradient(
                                            colors: [Color.accentFill, Color.accentFillPressed],
                                            startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(Color.accentFill.opacity(0.35)))
                                .frame(height: max(6, chartHeight * day.calories / peak))
                            Text(shortDayLabel(day.date))
                                .font(.system(size: 10))
                                .foregroundStyle(isToday ? Color.textPrimary : Color.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func shortDayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Bugün" }
        // 3-letter abbreviation (matches the day-rows list below) — a single
        // Turkish initial is ambiguous (Pazartesi/Perşembe/Pazar all start "P").
        return String(SofraFormatters.turkishShortWeekday.string(from: date).prefix(3)).capitalized
    }
}
