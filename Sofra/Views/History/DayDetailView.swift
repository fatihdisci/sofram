//
//  DayDetailView.swift
//  Sofra — calories, macros, meals and quick-adds for one day.
//

import SwiftData
import SwiftUI
import WidgetKit

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @Query(sort: \QuickAddItem.sortOrder)
    private var quickItems: [QuickAddItem]

    @Query private var quickCounts: [QuickAddCount]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000

    let date: Date

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 86_400)
    }

    private var dayScans: [ScanEntry] {
        scanEntries.filter { dayInterval.contains($0.timestamp) }
    }

    private var dayCounts: [QuickAddCount] {
        quickCounts.filter { dayInterval.contains($0.date) && $0.count > 0 }
    }

    private func quickAddSum(_ value: (QuickAddItem) -> Double) -> Double {
        dayCounts.reduce(0) { total, count in
            guard let item = quickItems.first(where: { $0.id == count.itemID }) else { return total }
            return total + Double(count.count) * value(item)
        }
    }

    private var calories: Double {
        dayScans.reduce(0) { $0 + $1.itemsOrEmpty.reduce(0) { $0 + $1.calories } }
            + quickAddSum { $0.caloriesPerUnit }
    }

    private var protein: Double {
        dayScans.reduce(0) { $0 + $1.itemsOrEmpty.reduce(0) { $0 + $1.protein } }
            + quickAddSum { $0.proteinPerUnit }
    }

    private var carbs: Double {
        dayScans.reduce(0) { $0 + $1.itemsOrEmpty.reduce(0) { $0 + $1.carbs } }
            + quickAddSum { $0.carbsPerUnit }
    }

    private var fat: Double {
        dayScans.reduce(0) { $0 + $1.itemsOrEmpty.reduce(0) { $0 + $1.fat } }
            + quickAddSum { $0.fatPerUnit }
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Layout.Spacing.xl) {
                    calorieSummary
                    macroSummary
                    mealsSection
                    quickAddsSection
                    Spacer(minLength: Layout.Spacing.xxl)
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, Layout.Spacing.md)
            }
        }
        .navigationTitle(Self.titleFormatter.string(from: date))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calorieSummary: some View {
        VStack(spacing: Layout.Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.surfaceFlat, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(calories / max(calorieTarget, 1), 1))
                    .stroke(Color.accentFill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(Int(calories.rounded()))")
                        .font(.sofraDisplayNumeric)
                        .foregroundStyle(Color.textPrimary)
                    Text("/ \(Int(calorieTarget)) kcal")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .frame(width: 132, height: 132)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var macroSummary: some View {
        HStack(spacing: 0) {
            macroCell("Protein", value: protein, color: .macroProtein)
            Divider().frame(height: 42).overlay(Color.borderHairline)
            macroCell("Karb.", value: carbs, color: .macroCarb)
            Divider().frame(height: 42).overlay(Color.borderHairline)
            macroCell("Yağ", value: fat, color: .macroFat)
        }
        .padding(Layout.Spacing.md)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private func macroCell(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(value.rounded())) g")
                .font(.sofraNumericSmall)
                .foregroundStyle(color)
            Text(label)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("ÖĞÜNLER")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            if dayScans.isEmpty {
                emptyRow("Bu gün için kayıtlı öğün yok.")
            } else {
                ForEach(dayScans, id: \.id) { entry in
                    MealEntryCard(entry: entry) {
                        delete(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var quickAddsSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("HIZLI EKLEMELER")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            if dayCounts.isEmpty {
                emptyRow("Bu gün için hızlı ekleme yok.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dayCounts.enumerated()), id: \.element.persistentModelID) { index, count in
                        if let item = quickItems.first(where: { $0.id == count.itemID }) {
                            HStack(spacing: Layout.Spacing.md) {
                                SofraIconView(icon: item.icon, size: 22)
                                    .foregroundStyle(Color.accentFill)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.sofraBody)
                                        .foregroundStyle(Color.textPrimary)
                                    Text(item.unit)
                                        .font(.sofraCaption)
                                        .foregroundStyle(Color.textMuted)
                                }
                                Spacer()
                                Text("\(count.count)")
                                    .font(.sofraNumericSmall)
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .padding(Layout.Spacing.lg)

                            if index < dayCounts.count - 1 {
                                Divider().overlay(Color.borderHairline)
                            }
                        }
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                .raisedSurface(cornerRadius: Layout.Radius.card)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.sofraBody)
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity)
            .padding(Layout.Spacing.xl)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
    }

    private func delete(_ entry: ScanEntry) {
        withAnimation(.sofraSpring) {
            modelContext.delete(entry)
            try? modelContext.save()
        }

        if Calendar.current.isDateInToday(date) {
            WidgetDataStore.saveCurrentDaySummary(
                modelContext: modelContext,
                calorieTarget: calorieTarget
            )
        }
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM EEEE"
        return formatter
    }()
}
