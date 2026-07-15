//
//  DailyView.swift
//  Calp — main daily screen after logging.
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

    @AppStorage("calp.dailyCalorieTarget") private var calorieTarget: Double = 2000
    @AppStorage("calp.proteinTarget") private var proteinTargetStored: Double = 0
    @AppStorage("calp.carbsTarget") private var carbsTargetStored: Double = 0
    @AppStorage("calp.fatTarget") private var fatTargetStored: Double = 0
    @State private var dayAnchor = Calendar.current.startOfDay(for: .now)
    @State private var healthSnapshot = HealthKitSnapshot.empty
    @State private var healthKitLoaded = false

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

    /// Calorie-bearing log groups become the quiet registration marks on the
    /// open Calp C. Scan entries preserve meal order; quick-add totals are
    /// appended as compact groups because their model stores a day, not a time.
    private var calorieSegments: [Double] {
        let scanSegments = todayScans
            .sorted { $0.timestamp < $1.timestamp }
            .map { entry in entry.itemsOrEmpty.reduce(0) { $0 + $1.calories } }
            .filter { $0 > 0 }

        let quickAddSegments = todayQuickCounts.compactMap { count -> Double? in
            guard count.count > 0,
                  let item = quickItems.first(where: { $0.id == count.itemID })
            else { return nil }
            let calories = Double(count.count) * item.caloriesPerUnit
            return calories > 0 ? calories : nil
        }

        return scanSegments + quickAddSegments
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
    @State private var showManualEntry = false
    @State private var editingLoggedItem: LoggedItem?

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

                    captureBar
                        .modifier(entrance(0.06))

                    CalorieRingView(
                        consumed: todayCalories,
                        target: calorieTarget,
                        calorieSegments: calorieSegments
                    )
                        .padding(.top, Layout.Spacing.sm)
                        .scaleEffect(appeared ? 1 : 0.82)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.08), value: appeared)

                    // Consumed / target pill — sits below the ring, outside it
                    consumedPill
                        .modifier(entrance(0.12))

                    macroSection
                        .modifier(entrance(0.16))

                    activeEnergySection
                        .modifier(entrance(0.2))

                    QuickCounterView()
                        .padding(.horizontal, Layout.Spacing.lg)
                        .modifier(entrance(0.24))

                    sevenDaySection

                    frequentMealsSection

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
                Task { await loadHealthSnapshot() }
            }
        }
        .task(id: dayAnchor) {
            await loadHealthSnapshot()
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView(calorieTarget: calorieTarget)
                .presentationCornerRadius(24)
                .presentationBackground(Color.bgPage)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingLoggedItem) { item in
            LoggedItemEditorView(item: item, calorieTarget: calorieTarget)
                .presentationCornerRadius(24)
                .presentationBackground(Color.bgPage)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.calpTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(todayLabel)
                    .font(.calpCaption)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
    }

    // MARK: - Capture bar (primary action)

    /// Search-like primary entry: a full-width prompt that reads as "the thing
    /// you do here". The camera fill is the accent; a text-log affordance sits
    /// alongside so both capture paths are found at a glance.
    private var captureBar: some View {
        HStack(spacing: Layout.Spacing.md) {
            Button {
                nav.goToCamera()
            } label: {
                HStack(spacing: Layout.Spacing.md) {
                    CalpIconView(icon: .capture, size: 20)
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.accentFill))
                    Text("Tabağını çek, kalorisini gör")
                        .font(.calpBody)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(Layout.Spacing.sm)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                .raisedSurface(cornerRadius: Layout.Radius.card)
            }
            .accessibilityLabel(String(localized: "Fotoğrafla ekle"))
            .buttonStyle(CalpPressButtonStyle(cornerRadius: Layout.Radius.card))

            Button {
                nav.goToTextLog(from: .daily)
            } label: {
                CalpIconView(icon: .mealNote, size: 22)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 56, height: 56)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                    .raisedSurface(cornerRadius: Layout.Radius.card)
            }
            .accessibilityLabel(String(localized: "Yazarak ekle"))
        }
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - Consumed / target pill (below ring)

    private var consumedPill: some View {
        Text("\(Int(todayCalories)) / \(Int(calorieTarget)) kcal")
            .font(.calpNumericSmall)
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
                .font(.calpEyebrow)
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

    // MARK: - Active energy

    private var activeEnergySection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("HAREKET")
                .font(.calpEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            HStack(spacing: Layout.Spacing.md) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentFill)
                    .frame(width: 40, height: 40)
                    .background(Color.accentTintBg, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Aktif enerji")
                        .font(.calpLabel)
                        .foregroundStyle(Color.textPrimary)
                    Text(healthSnapshot.steps > 0
                         ? "\(Int(healthSnapshot.steps.rounded())) adım"
                         : "HealthKit verisi cihazda tutulur")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(healthSnapshot.activeEnergyKcal > 0
                         ? "\(Int(healthSnapshot.activeEnergyKcal.rounded()))"
                         : "—")
                        .font(.calpNumericSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text("kcal")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)

            if healthKitLoaded && healthSnapshot.activeEnergyKcal == 0 && healthSnapshot.steps == 0 {
                Button {
                    nav.selectedTab = .settings
                } label: {
                    Label("Sağlık verilerini Ayarlar’dan bağla", systemImage: "heart.text.square")
                        .font(.calpCaption)
                        .foregroundStyle(Color.accentText)
                }
                .padding(.horizontal, Layout.Spacing.sm)
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
    }

    @MainActor
    private func loadHealthSnapshot() async {
        let snapshot = await HealthKitManager.shared.readToday()
        guard !Task.isCancelled else { return }
        healthSnapshot = snapshot
        healthKitLoaded = true
    }

    // MARK: - 7-day section

    private var sevenDaySection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("BU HAFTA")
                .font(.calpEyebrow)
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
                        .font(.calpLabel)
                        .foregroundStyle(Color.textPrimary)
                    Text(weekAverage > 0 ? String(localized: "Ortalama \(Int(weekAverage)) kcal") : String(localized: "Henüz veri yok"))
                        .font(.calpCaption)
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
        .buttonStyle(CalpPressButtonStyle(cornerRadius: Layout.Radius.card))
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

    // MARK: - Frequent meals

    private var frequentMeals: [FrequentMeal] {
        FrequentMealsBuilder.build(scans: scanEntries)
    }

    @ViewBuilder
    private var frequentMealsSection: some View {
        if !frequentMeals.isEmpty {
            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                Text("SIK EKLENENLER")
                    .font(.calpEyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Color.textMuted)

                ForEach(frequentMeals) { meal in
                    Button {
                        addFrequentMeal(meal)
                    } label: {
                        HStack(spacing: Layout.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name)
                                    .font(.calpLabel)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(2)
                                Text("\(Int(meal.totalCalories)) kcal · \(meal.usageCount)x")
                                    .font(.calpCaption)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.accentFill)
                                .accessibilityLabel(String(localized: "Öğünü ekle"))
                        }
                        .padding(Layout.Spacing.lg)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                        .raisedSurface(cornerRadius: Layout.Radius.card)
                    }
                    .buttonStyle(CalpPressButtonStyle(cornerRadius: Layout.Radius.card))
                    .accessibilityLabel(String(localized: "\(meal.name), \(Int(meal.totalCalories)) kilokalori, ekle"))
                }
            }
            .padding(.horizontal, Layout.Spacing.lg)
        }
    }

    private func addFrequentMeal(_ meal: FrequentMeal) {
        withAnimation(.calpSpring) {
            let entry = FrequentMealsBuilder.deepCopy(meal, into: modelContext)
            try? modelContext.save()
            let externalID = entry.id
            let mealDate = entry.timestamp
            Task {
                _ = await HealthKitManager.shared.syncMealNutrition(
                    externalID: externalID,
                    date: mealDate,
                    calories: meal.totalCalories,
                    protein: meal.totalProtein,
                    carbs: meal.totalCarbs,
                    fat: meal.totalFat
                )
            }
        }
        WidgetDataStore.saveCurrentDaySummary(modelContext: modelContext, calorieTarget: calorieTarget)
        MealReminderService.shared.reschedule(modelContext: modelContext)
    }

    // MARK: - Today's entries

    @ViewBuilder
    private var todayEntriesSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack {
                Text("BUGÜNKÜ ÖĞÜNLER")
                    .font(.calpEyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Button {
                    showManualEntry = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Elle gir")
                            .font(.calpCaption)
                    }
                    .foregroundStyle(Color.accentText)
                }
            }
            .padding(.horizontal, Layout.Spacing.lg)

            if todayScans.isEmpty {
                emptyMealsCard
            } else {
                ForEach(todayScans, id: \.id) { entry in
                    MealEntryCard(
                        entry: entry,
                        onEdit: { item in editingLoggedItem = item },
                        onDelete: { delete(entry) }
                    )
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
            // Purpose-built static empty graphic: an empty plate on a flat
            // surface disc. Deliberately motionless — nothing is "waiting", so
            // there is no perpetual animation (and nothing to disable under
            // Reduce Motion). If a brand-approved calp_empty_plate.json is ever
            // added, this is the one place to swap back to CalpLottieView.
            ZStack {
                Circle()
                    .fill(Color.surfaceFlat)
                    .frame(width: 80, height: 80)
                CalpIconView(icon: .emptyPlate, size: 40)
                    .foregroundStyle(Color.textMuted)
            }
            .accessibilityHidden(true)

            Text("Bugün henüz öğün eklemedin")
                .font(.calpBody)
                .foregroundStyle(Color.textPrimary)

            Text("Tabağının fotoğrafını çek, gerisini Calp halletsin.")
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: Layout.Spacing.md) {
                Button {
                    nav.goToCamera()
                } label: {
                    HStack(spacing: 6) {
                        CalpIconView(icon: .capture, size: 16)
                        Text("Fotoğrafla ekle")
                            .font(.calpLabel)
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
                        .font(.calpLabel)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, Layout.Spacing.lg)
                        .padding(.vertical, Layout.Spacing.sm)
                        .background(Color.surfaceFlat, in: Capsule())
                }
            }
            .padding(.top, Layout.Spacing.xs)

            Button {
                showManualEntry = true
            } label: {
                Text("Ya da kalori/makroyu elle gir")
                    .font(.calpCaption)
                    .foregroundStyle(Color.accentText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer))
        .raisedSurface(cornerRadius: Layout.Radius.raisedContainer)
        .padding(.horizontal, Layout.Spacing.lg)
    }

    private func delete(_ entry: ScanEntry) {
        let externalID = entry.id
        withAnimation(.calpSpring) {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        Task {
            _ = await HealthKitManager.shared.deleteMealNutrition(externalID: externalID)
        }
        WidgetDataStore.saveCurrentDaySummary(
            modelContext: modelContext,
            calorieTarget: calorieTarget
        )
        MealReminderService.shared.reschedule(modelContext: modelContext)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return String(localized: "Günaydın")
        case 11..<18: return String(localized: "İyi günler")
        default:      return String(localized: "İyi akşamlar")
        }
    }

    private var todayLabel: String {
        CalpFormatters.turkishFullDay.string(from: dayAnchor)
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
                .font(.calpCaption)
                .foregroundStyle(Color.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))")
                    .font(.calpNumericSmall)
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
                let barHeight = max(8, 30 * day.calories / peak)
                // "Today" is signalled by a small tick beneath the bar, not by
                // colour/opacity alone (a11y: never colour as the sole cue).
                VStack(spacing: 3) {
                    Capsule()
                        .fill(isToday
                            ? AnyShapeStyle(Color.accentFill)
                            : AnyShapeStyle(Color.accentFill.opacity(0.35)))
                        .frame(width: isToday ? 6 : 5, height: barHeight)
                    Circle()
                        .fill(isToday ? Color.accentFill : Color.clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Meal entry card

struct MealEntryCard: View {
    let entry: ScanEntry
    let onEdit: (LoggedItem) -> Void
    let onDelete: () -> Void

    private var entryCalories: Double {
        entry.itemsOrEmpty.reduce(0) { $0 + $1.calories }
    }

    private var timeLabel: String {
        CalpFormatters.time.string(from: entry.timestamp)
    }

    private var sourceIcon: String {
        switch entry.source {
        case .photo:  return "camera.fill"
        case .text:   return "text.alignleft"
        case .manual: return "square.and.pencil"
        }
    }

    var body: some View {
        VStack(spacing: Layout.Spacing.sm) {
            // Entry header: time + source + total
            HStack(spacing: Layout.Spacing.xs) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
                Text(timeLabel)
                    .font(.calpCaption)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("\(Int(entryCalories)) kcal")
                    .font(.calpNumericSmall)
                    .foregroundStyle(Color.accentText)
                    .contentTransition(.numericText())
            }

            Divider().overlay(Color.borderHairline)

            ForEach(entry.itemsOrEmpty, id: \.persistentModelID) { item in
                Button {
                    onEdit(item)
                } label: {
                    HStack(spacing: Layout.Spacing.sm) {
                        CalpIconView(icon: item.portionUnit.icon ?? .tabak, size: 20)
                            .foregroundStyle(Color.accentFill)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.calpBody)
                                .foregroundStyle(Color.textPrimary)
                            Text("\(item.quantity, specifier: "%.1f") \(item.portionUnit.displayName)")
                                .font(.calpCaption)
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Text("\(Int(item.calories)) kcal")
                            .font(.calpNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öğeyi düzenler")
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

// MARK: - Manual entry (one-off meal — free, no scan consumed)

/// Type calories (+ optional macros) and it writes a `.manual` ScanEntry into
/// today. No AI scan is consumed and no persistent counter is created; the entry
/// shows up in Today and History like any other and is deletable there.
///
/// Lives in this file (like SettingsView in ContentView) so it compiles against
/// the committed .xcodeproj without a `xcodegen generate` step.
struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Today's calorie target, forwarded to the widget snapshot after saving.
    let calorieTarget: Double

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""

    private enum Field: Hashable { case name, calories, protein, carbs, fat }
    @FocusState private var focusedField: Field?

    private var calories: Double { parse(caloriesText) }
    private var canSave: Bool { calories > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad (opsiyonel, örn. akşam yemeği)", text: $name)
                        .focused($focusedField, equals: .name)
                } footer: {
                    Text("Boş bırakırsan “Elle giriş” olarak kaydedilir.")
                }

                Section {
                    nutrientRow(title: "Kalori", text: $caloriesText, unit: "kcal", field: .calories)
                    nutrientRow(title: "Protein", text: $proteinText, unit: "g", field: .protein)
                    nutrientRow(title: "Karbonhidrat", text: $carbsText, unit: "g", field: .carbs)
                    nutrientRow(title: "Yağ", text: $fatText, unit: "g", field: .fat)
                } header: {
                    Text("Besin değeri")
                } footer: {
                    Text("Yalnız kalori zorunlu. Bugüne eklenir — ücretsizdir, tarama hakkından düşmez.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPage.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Elle Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { save() }.disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.accentFill)
    }

    private func nutrientRow(title: String, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .font(.calpNumericSmall)
                .focused($focusedField, equals: field)
            Text(unit)
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let entry = ScanEntry(source: .manual)
        let item = LoggedItem(
            name: trimmed.isEmpty ? String(localized: "Elle giriş") : trimmed,
            portionUnit: .adet,
            quantity: 1,
            calories: calories,
            protein: parse(proteinText),
            carbs: parse(carbsText),
            fat: parse(fatText),
            confidence: 1,
            valueSource: "manual"
        )
        item.scanEntry = entry
        entry.items = [item]
        modelContext.insert(entry)
        try? modelContext.save()

        let externalID = entry.id
        let mealDate = entry.timestamp
        let mealCalories = item.calories
        let mealProtein = item.protein
        let mealCarbs = item.carbs
        let mealFat = item.fat
        Task {
            _ = await HealthKitManager.shared.syncMealNutrition(
                externalID: externalID,
                date: mealDate,
                calories: mealCalories,
                protein: mealProtein,
                carbs: mealCarbs,
                fat: mealFat
            )
        }

        WidgetDataStore.saveCurrentDaySummary(modelContext: modelContext, calorieTarget: calorieTarget)
        MealReminderService.shared.reschedule(modelContext: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    /// Accepts both "," and "." as the decimal separator (Turkish keyboards).
    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

// MARK: - Logged meal editor

/// Edits a saved AI or manual item in place. Portion changes preserve the
/// item's per-portion density; the optional manual mode is for correcting an
/// uncertain AI estimate without having to delete and create the meal again.
struct LoggedItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: LoggedItem
    let calorieTarget: Double

    private let originalQuantity: Double
    private let originalEstimatedGrams: Double
    private let originalCalories: Double
    private let originalProtein: Double
    private let originalCarbs: Double
    private let originalFat: Double

    @State private var name: String
    @State private var portionUnit: PortionUnit
    @State private var quantity: Double
    @State private var isManuallyEditingMacros = false
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    private enum Field: Hashable { case name, calories, protein, carbs, fat }
    @FocusState private var focusedField: Field?

    init(item: LoggedItem, calorieTarget: Double) {
        self.item = item
        self.calorieTarget = calorieTarget
        self.originalQuantity = max(item.quantity, 1)
        self.originalEstimatedGrams = item.estimatedGrams
        self.originalCalories = item.calories
        self.originalProtein = item.protein
        self.originalCarbs = item.carbs
        self.originalFat = item.fat
        _name = State(initialValue: item.name)
        _portionUnit = State(initialValue: item.portionUnit)
        _quantity = State(initialValue: max(item.quantity, 1))
        _caloriesText = State(initialValue: Self.numberString(item.calories))
        _proteinText = State(initialValue: Self.numberString(item.protein))
        _carbsText = State(initialValue: Self.numberString(item.carbs))
        _fatText = State(initialValue: Self.numberString(item.fat))
    }

    private var quantityScale: Double { quantity / originalQuantity }
    private var estimatedGrams: Double { originalEstimatedGrams * quantityScale }
    private var calories: Double { isManuallyEditingMacros ? parse(caloriesText) : originalCalories * quantityScale }
    private var protein: Double { isManuallyEditingMacros ? parse(proteinText) : originalProtein * quantityScale }
    private var carbs: Double { isManuallyEditingMacros ? parse(carbsText) : originalCarbs * quantityScale }
    private var fat: Double { isManuallyEditingMacros ? parse(fatText) : originalFat * quantityScale }

    private var quantityStep: Double {
        switch portionUnit {
        case .adet, .dilim: return 1
        default: return 0.5
        }
    }

    private var quantityMinimum: Double {
        switch portionUnit {
        case .dilim: return 0.5
        default: return 1
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Öğe") {
                    TextField("Yemek adı", text: $name)
                        .focused($focusedField, equals: .name)
                }

                Section("Porsiyon") {
                    Picker("Birim", selection: $portionUnit) {
                        ForEach(PortionUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }

                    Stepper(value: $quantity, in: quantityMinimum...20, step: quantityStep) {
                        HStack {
                            Text("Miktar")
                            Spacer()
                            Text("\(quantity, specifier: "%.1f") \(portionUnit.displayName)")
                                .font(.calpNumericSmall)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }

                    if estimatedGrams > 0 {
                        LabeledContent("Tahmini ağırlık") {
                            Text("~\(Int(estimatedGrams.rounded())) g")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Section {
                    Toggle("Besin değerlerini elle düzenle", isOn: $isManuallyEditingMacros)
                        .onChange(of: isManuallyEditingMacros) { _, isEditing in
                            if isEditing { loadScaledMacroValues() }
                        }

                    if isManuallyEditingMacros {
                        nutrientRow(title: "Kalori", text: $caloriesText, unit: "kcal", field: .calories)
                        nutrientRow(title: "Protein", text: $proteinText, unit: "g", field: .protein)
                        nutrientRow(title: "Karbonhidrat", text: $carbsText, unit: "g", field: .carbs)
                        nutrientRow(title: "Yağ", text: $fatText, unit: "g", field: .fat)
                    } else {
                        previewRow(title: "Kalori", value: calories, unit: "kcal")
                        previewRow(title: "Protein", value: protein, unit: "g")
                        previewRow(title: "Karbonhidrat", value: carbs, unit: "g")
                        previewRow(title: "Yağ", value: fat, unit: "g")
                    }
                } header: {
                    Text("Besin değerleri")
                } footer: {
                    Text(isManuallyEditingMacros
                         ? "Elle girdiğin değerler kaydedilir."
                         : "Miktarı değiştirdiğinde besin değerleri orantılı güncellenir.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPage.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Öğeyi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.accentFill)
    }

    private func previewRow(title: String, value: Double, unit: String) -> some View {
        LabeledContent(title) {
            Text("\(Self.numberString(value)) \(unit)")
                .font(.calpNumericSmall)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func nutrientRow(title: String, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 78)
                .font(.calpNumericSmall)
                .focused($focusedField, equals: field)
            Text(unit)
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
        }
    }

    private func loadScaledMacroValues() {
        caloriesText = Self.numberString(originalCalories * quantityScale)
        proteinText = Self.numberString(originalProtein * quantityScale)
        carbsText = Self.numberString(originalCarbs * quantityScale)
        fatText = Self.numberString(originalFat * quantityScale)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        item.name = trimmedName
        item.portionUnit = portionUnit
        item.quantity = quantity
        item.estimatedGrams = estimatedGrams
        item.calories = calories
        item.protein = protein
        item.carbs = carbs
        item.fat = fat
        try? modelContext.save()

        if let entry = item.scanEntry {
            let externalID = entry.id
            let mealDate = entry.timestamp
            let mealTotals = entry.itemsOrEmpty.reduce(into: (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0)) { totals, item in
                totals.calories += item.calories
                totals.protein += item.protein
                totals.carbs += item.carbs
                totals.fat += item.fat
            }
            Task {
                _ = await HealthKitManager.shared.syncMealNutrition(
                    externalID: externalID,
                    date: mealDate,
                    calories: mealTotals.calories,
                    protein: mealTotals.protein,
                    carbs: mealTotals.carbs,
                    fat: mealTotals.fat
                )
            }
        }

        WidgetDataStore.saveCurrentDaySummary(modelContext: modelContext, calorieTarget: calorieTarget)
        MealReminderService.shared.reschedule(modelContext: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func numberString(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
