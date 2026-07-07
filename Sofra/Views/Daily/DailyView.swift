//
//  DailyView.swift
//  Sofra — main daily screen after logging.
//
//  Central calorie ring + macro readouts + bread/tea quick counters
//  + access to 7-day summary. Camera button at top returns to capture.
//

import SwiftUI
import SwiftData

struct DailyView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @Query(sort: \DailyQuickCounter.date, order: .reverse)
    private var counters: [DailyQuickCounter]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000

    /// Today's scan entries.
    private var todayScans: [ScanEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        return scanEntries.filter { entry in
            entry.timestamp >= today && entry.timestamp < tomorrow
        }
    }

    /// Today's total macros.
    private var todayCalories: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.calories } }
    }
    private var todayProtein: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.protein } }
    }
    private var todayCarbs: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.carbs } }
    }
    private var todayFat: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.fat } }
    }

    /// Today's quick counter (fetched or new).
    @State private var breadSlices: Int = 0
    @State private var teaGlasses: Int = 0

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Layout.Spacing.xl) {
                    // Top bar
                    topBar

                    // Calorie ring
                    CalorieRingView(consumed: todayCalories, target: calorieTarget)
                        .padding(.top, Layout.Spacing.md)

                    // Macro readouts
                    macroRow

                    // Quick counters
                    QuickCounterView(
                        breadSlices: $breadSlices,
                        teaGlasses: $teaGlasses
                    )
                    .padding(.horizontal, Layout.Spacing.lg)

                    // 7-day summary link
                    sevenDayButton

                    // Today's entries
                    if !todayScans.isEmpty {
                        todayEntriesSection
                    }

                    Spacer(minLength: 120)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { nav.showSevenDaySummary },
            set: { nav.showSevenDaySummary = $0 }
        )) {
            SevenDaySummaryView()
        }
        .onAppear { loadTodayCounters() }
        .onChange(of: breadSlices) { _, _ in saveCounters() }
        .onChange(of: teaGlasses) { _, _ in saveCounters() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(todayLabel)
                    .font(.sofraTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Günlük Özet")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            // Camera button
            Button {
                nav.goToCamera()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.onAccent)
                    .padding(Layout.Spacing.md)
                    .background(Color.accentFill, in: Circle())
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, 60)
    }

    // MARK: - Macro row

    private var macroRow: some View {
        HStack(spacing: Layout.Spacing.xl) {
            MacroPill(label: "Protein", value: todayProtein, unit: "g", color: .green)
            MacroPill(label: "Carbs", value: todayCarbs, unit: "g", color: .orange)
            MacroPill(label: "Yağ", value: todayFat, unit: "g", color: .red.opacity(0.8))
        }
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - 7-day summary button

    private var sevenDayButton: some View {
        Button {
            nav.showSevenDaySummary = true
        } label: {
            HStack(spacing: Layout.Spacing.sm) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13))
                Text("7 Günlük Özet")
                    .font(.sofraLabel)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - Today's entries

    private var todayEntriesSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("Bugünkü Öğünler")
                .font(.sofraLabel)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Layout.Spacing.lg)

            ForEach(todayScans, id: \.id) { entry in
                VStack(spacing: Layout.Spacing.xs) {
                    ForEach(entry.itemsOrEmpty, id: \.persistentModelID) { item in
                        HStack(spacing: Layout.Spacing.sm) {
                            SofraIconView(icon: item.portionUnit.icon ?? .tabak, size: 20)
                                .foregroundStyle(Color.accentFill)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.sofraBody)
                                    .foregroundStyle(Color.textPrimary)
                                Text("\(item.quantity, specifier: "%.1f") \(item.portionUnit.displayName)")
                                    .font(.sofraCaption)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            Text("\(Int(item.calories)) kcal")
                                .font(.sofraNumericSmall)
                                .foregroundStyle(Color.accentText)
                        }
                    }
                }
                .padding(Layout.Spacing.md)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                .padding(.horizontal, Layout.Spacing.lg)
            }
        }
    }

    // MARK: - Counters persistence

    private func loadTodayCounters() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let todayCounter = counters.first(where: { counter in
            counter.date >= today && counter.date < cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        }) {
            breadSlices = todayCounter.breadSlices
            teaGlasses = todayCounter.teaGlasses
        }
    }

    private func saveCounters() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Find existing counter for today or create one
        if let existing = counters.first(where: { counter in
            counter.date >= today && counter.date < cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        }) {
            existing.breadSlices = breadSlices
            existing.teaGlasses = teaGlasses
        } else {
            let new = DailyQuickCounter(date: today, breadSlices: breadSlices, teaGlasses: teaGlasses)
            modelContext.insert(new)
        }
        try? modelContext.save()
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: Date())
    }
}

// MARK: - Macro pill

struct MacroPill: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(value))")
                .font(.sofraNumericSmall)
                .foregroundStyle(Color.textPrimary)
            Text("\(label)")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Spacing.md)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Layout.Radius.control))
    }
}
