//
//  DailyView.swift
//  Sofra — main daily screen after logging.
//
//  Greeting + date header, central calorie ring, macro progress cards,
//  bread/tea quick counters, a 7-day sparkline card and today's meals
//  (with delete). Camera and text-log entry points live in the header
//  and in the empty state.
//

import SwiftUI
import SwiftData
import WidgetKit

struct DailyView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @Query(sort: \QuickAddItem.sortOrder)
    private var quickItems: [QuickAddItem]

    @Query private var quickCounts: [QuickAddCount]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000
    @AppStorage("sofra.proteinTarget") private var proteinTargetStored: Double = 0
    @AppStorage("sofra.carbsTarget") private var carbsTargetStored: Double = 0
    @AppStorage("sofra.fatTarget") private var fatTargetStored: Double = 0
    @State private var dayAnchor = Calendar.current.startOfDay(for: .now)

    /// Today's scan entries.
    private var todayScans: [ScanEntry] {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: dayAnchor) ?? dayAnchor
        return scanEntries.filter { entry in
            entry.timestamp >= dayAnchor && entry.timestamp < tomorrow
        }
    }

    /// Today's quick-add tallies and the calories they contribute.
    private var todayQuickCounts: [QuickAddCount] {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: dayAnchor) ?? dayAnchor
        return quickCounts.filter { $0.date >= dayAnchor && $0.date < tomorrow }
    }

    /// Sum of `perUnit(item) × count` over today's quick-add tallies.
    private func quickAddSum(_ perUnit: (QuickAddItem) -> Double) -> Double {
        todayQuickCounts.reduce(0) { sum, c in
            guard let item = quickItems.first(where: { $0.id == c.itemID }) else { return sum }
            return sum + Double(c.count) * perUnit(item)
        }
    }

    /// Today's totals — scans + calorie/macro-bearing quick-adds contribute to
    /// both the ring and the macro cards.
    private var todayCalories: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.calories } }
            + quickAddSum { $0.caloriesPerUnit }
    }
    private var todayProtein: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.protein } }
            + quickAddSum { $0.proteinPerUnit }
    }
    private var todayCarbs: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.carbs } }
            + quickAddSum { $0.carbsPerUnit }
    }
    private var todayFat: Double {
        todayScans.reduce(0) { $0 + ($1.itemsOrEmpty).reduce(0) { $0 + $1.fat } }
            + quickAddSum { $0.fatPerUnit }
    }

    /// Macro gram targets. User-set values (from Ayarlar) win; otherwise fall
    /// back to a derived P25 · K45 · Y30 split of the calorie target.
    private var proteinTarget: Double { proteinTargetStored > 0 ? proteinTargetStored : calorieTarget * 0.25 / 4 }
    private var carbsTarget: Double { carbsTargetStored > 0 ? carbsTargetStored : calorieTarget * 0.45 / 4 }
    private var fatTarget: Double { fatTargetStored > 0 ? fatTargetStored : calorieTarget * 0.30 / 9 }

    private var weekSummaries: [DaySummary] {
        DaySummaryBuilder.lastSevenDays(scans: scanEntries, items: quickItems, counts: quickCounts)
    }

    /// First-appear entrance: one `appeared` trigger, each element animates in
    /// with its own delay for a clear top-to-bottom cascade. Below-the-fold
    /// cards get their motion from `.scrollTransition` instead.
    @State private var appeared = false

    private func entrance(_ delay: Double) -> some ViewModifier {
        EntranceModifier(appeared: appeared, delay: delay)
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Layout.Spacing.xl) {
                    topBar
                        .modifier(entrance(0))

                    CalorieRingView(consumed: todayCalories, target: calorieTarget)
                        .padding(.top, Layout.Spacing.sm)
                        .scaleEffect(appeared ? 1 : 0.82)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.08), value: appeared)

                    // Consumed / target pill — sits below the ring, outside it
                    consumedPill
                        .modifier(entrance(0.12))

                    macroSection
                        .modifier(entrance(0.16))

                    QuickCounterView()
                        .padding(.horizontal, Layout.Spacing.lg)
                        .modifier(entrance(0.24))

                    sevenDaySection

                    todayEntriesSection

                    // Safe area for tab bar clearance
                    Spacer(minLength: 96)
                }
            }
        }
        .onAppear {
            refreshDayAnchor()
            if !appeared { appeared = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshDayAnchor()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshDayAnchor()
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.sofraTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(todayLabel)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            // Text log
            Button {
                nav.goToTextLog(from: .daily)
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 46, height: 46)
                    .background(Color.surfaceRaised, in: Circle())
                    .raisedSurface(cornerRadius: 23)
            }

            // Camera — the primary action
            Button {
                nav.goToCamera()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle().fill(
                            Color.accentFill
                                .shadow(.drop(color: .borderShadow.opacity(0.6), radius: 5, x: 3, y: 3))
                        )
                    )
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
    }

    // MARK: - Consumed / target pill (below ring)

    private var consumedPill: some View {
        Text("\(Int(todayCalories)) / \(Int(calorieTarget)) kcal")
            .font(.sofraNumericSmall)
            .foregroundStyle(Color.accentText)
            .contentTransition(.numericText())
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, 6)
            .background(Color.accentTintBg, in: Capsule())
    }

    // MARK: - Macro section (unified card, 3 columns)

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("MAKROLAR")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            HStack(spacing: 0) {
                UnifiedMacroColumn(label: "Protein", value: todayProtein, target: proteinTarget, color: .macroProtein)
                Divider().frame(height: 48).overlay(Color.borderHairline)
                UnifiedMacroColumn(label: "Karb.", value: todayCarbs, target: carbsTarget, color: .macroCarb)
                Divider().frame(height: 48).overlay(Color.borderHairline)
                UnifiedMacroColumn(label: "Yağ", value: todayFat, target: fatTarget, color: .macroFat)
            }
            .padding(Layout.Spacing.md)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)
        }
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - 7-day section

    private var sevenDaySection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("BU HAFTA")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            sevenDayCard
        }
        .padding(.horizontal, Layout.Spacing.lg)
    }

    private var sevenDayCard: some View {
        Button {
            nav.selectedTab = .history
        } label: {
            HStack(spacing: Layout.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("7 Günlük Özet")
                        .font(.sofraLabel)
                        .foregroundStyle(Color.textPrimary)
                    Text(weekAverage > 0 ? "Ortalama \(Int(weekAverage)) kcal" : "Henüz veri yok")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                WeekSparkline(summaries: weekSummaries, target: calorieTarget)
                    .frame(width: 96, height: 36)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)
        }
        .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.4)
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .offset(y: phase.isIdentity ? 0 : 12)
        }
    }

    private var weekAverage: Double {
        let days = weekSummaries.filter { $0.calories > 0 }
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.calories } / Double(days.count)
    }

    // MARK: - Today's entries

    @ViewBuilder
    private var todayEntriesSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("BUGÜNKÜ ÖĞÜNLER")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, Layout.Spacing.lg)

            if todayScans.isEmpty {
                emptyMealsCard
            } else {
                ForEach(todayScans, id: \.id) { entry in
                    MealEntryCard(entry: entry) {
                        delete(entry)
                    }
                    .padding(.horizontal, Layout.Spacing.lg)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.4)
                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                            .offset(y: phase.isIdentity ? 0 : 12)
                    }
                }
            }
        }
    }

    private var emptyMealsCard: some View {
        VStack(spacing: Layout.Spacing.md) {
            // Lottie asset'i gelene kadar marka ikonunun kasıtlı nefes fallback'i.
            SofraLottieView("sofra_empty_plate", speed: 0.85) {
                SofraPulseShine {
                    SofraIconView(icon: .sofra, size: 44)
                        .foregroundStyle(Color.accentFill)
                }
            }
            .frame(width: 80, height: 80)

            Text("Bugün henüz öğün eklemedin")
                .font(.sofraBody)
                .foregroundStyle(Color.textPrimary)

            Text("Tabağının fotoğrafını çek, gerisini Sofra halletsin.")
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: Layout.Spacing.md) {
                Button {
                    nav.goToCamera()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13))
                        Text("Fotoğrafla ekle")
                            .font(.sofraLabel)
                    }
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.sm)
                    .background(Color.accentFill, in: Capsule())
                }

                Button {
                    nav.goToTextLog(from: .daily)
                } label: {
                    Text("Yazarak ekle")
                        .font(.sofraLabel)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, Layout.Spacing.lg)
                        .padding(.vertical, Layout.Spacing.sm)
                        .background(Color.surfaceFlat, in: Capsule())
                }
            }
            .padding(.top, Layout.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer))
        .raisedSurface(cornerRadius: Layout.Radius.raisedContainer)
        .padding(.horizontal, Layout.Spacing.lg)
    }

    private func delete(_ entry: ScanEntry) {
        withAnimation(.sofraSpring) {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        WidgetDataStore.saveCurrentDaySummary(
            modelContext: modelContext,
            calorieTarget: calorieTarget
        )
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return "Günaydın"
        case 11..<18: return "İyi günler"
        default:      return "İyi akşamlar"
        }
    }

    private var todayLabel: String {
        SofraFormatters.turkishFullDay.string(from: dayAnchor)
    }

    private func refreshDayAnchor() {
        dayAnchor = Calendar.current.startOfDay(for: .now)
    }
}

// MARK: - Entrance modifier (fade + rise, with a per-element delay)

private struct EntranceModifier: ViewModifier {
    let appeared: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0.4)
            .scaleEffect(appeared ? 1 : 0.96)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay), value: appeared)
    }
}

// MARK: - Unified macro column (single card, 3 columns)

struct UnifiedMacroColumn: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(value / target, 1)
    }

    var body: some View {
        VStack(alignment: .center, spacing: Layout.Spacing.xs) {
            Text(label)
                .font(.sofraCaption)
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                Text("/ \(Int(target)) g")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
            }

            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceFlat)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 4 : 0))
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Week sparkline (mini 7-bar chart, oldest → newest)

struct WeekSparkline: View {
    let summaries: [DaySummary]   // today first
    let target: Double

    var body: some View {
        let ordered = Array(summaries.reversed())
        let peak = max(ordered.map(\.calories).max() ?? 0, target, 1)

        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { idx, day in
                let isToday = idx == ordered.count - 1
                let barHeight = max(8, 36 * day.calories / peak)
                Capsule()
                    .fill(isToday
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.accentFill, Color.accentFillPressed],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.accentFill.opacity(0.35)))
                    .frame(width: isToday ? 6 : 5, height: barHeight)
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: - Meal entry card

struct MealEntryCard: View {
    let entry: ScanEntry
    let onDelete: () -> Void

    private var entryCalories: Double {
        entry.itemsOrEmpty.reduce(0) { $0 + $1.calories }
    }

    private var timeLabel: String {
        SofraFormatters.time.string(from: entry.timestamp)
    }

    var body: some View {
        VStack(spacing: Layout.Spacing.sm) {
            // Entry header: time + source + total
            HStack(spacing: Layout.Spacing.xs) {
                Image(systemName: entry.source == .photo ? "camera.fill" : "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
                Text(timeLabel)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("\(Int(entryCalories)) kcal")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.accentText)
                    .contentTransition(.numericText())
            }

            Divider().overlay(Color.borderHairline)

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
                        .foregroundStyle(Color.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Öğünü Sil", systemImage: "trash")
            }
        }
    }
}
