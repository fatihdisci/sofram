//
//  QuickCounterView.swift
//  Calorisor — customizable quick-add counters.
//
//  Users define their own counters (name / unit / icon / optional calories),
//  reorder them, and tally them per day. Replaces the hardcoded bread/tea pair.
//
//  Per mikro-etkilesimler.md:
//  - Each tap: .impact(light) haptic + "+1" ghost text fades upward (400ms)
//  - No shaming/warning for high counts — neutral data only.
//  - An explicit "-" button appears once count > 0 (mis-tap recovery), medium
//    haptic + "-1" ghost. Not a long-press: a hidden gesture was undiscoverable
//    and conflicted with the tap-to-increment gesture on the same view.
//

import SwiftUI
import SwiftData
import WidgetKit

struct QuickCounterView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \QuickAddItem.sortOrder) private var items: [QuickAddItem]
    @Query private var allCounts: [QuickAddCount]

    @AppStorage("calorisor.dailyCalorieTarget") private var calorieTarget: Double = 2000

    @State private var editingItem: QuickAddItem?
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack {
                Text("HIZLI EKLE")
                    .font(.sofraEyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Button {
                    editingItem = nil
                    showEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Ekle")
                            .font(.sofraCaption)
                    }
                    .foregroundStyle(Color.accentText)
                }
            }

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: Layout.Spacing.sm) {
                    ForEach(items) { item in
                        QuickChip(
                            item: item,
                            count: count(for: item),
                            onIncrement: { increment(item) },
                            onDecrement: { decrement(item) },
                            onEdit: { editingItem = item; showEditor = true },
                            onDelete: { delete(item) }
                        )
                    }
                }
            }
        }
        .onAppear { QuickAddSeed.seedDefaultsIfNeeded(modelContext) }
        .sheet(isPresented: $showEditor) {
            QuickAddEditorView(item: editingItem, nextSortOrder: (items.map(\.sortOrder).max() ?? -1) + 1)
                .presentationCornerRadius(24)
                .presentationBackground(Color.bgPage)
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        Button {
            editingItem = nil
            showEditor = true
        } label: {
            HStack(spacing: Layout.Spacing.sm) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                Text("İlk hızlı ekleme sayacını oluştur")
                    .font(.sofraCaption)
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today's counts

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var todayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
    }

    private func todayCount(for item: QuickAddItem) -> QuickAddCount? {
        allCounts.first { $0.itemID == item.id && $0.date >= todayStart && $0.date < todayEnd }
    }

    private func count(for item: QuickAddItem) -> Int {
        todayCount(for: item)?.count ?? 0
    }

    // MARK: - Mutations

    private func increment(_ item: QuickAddItem) {
        if let existing = todayCount(for: item) {
            existing.count += 1
        } else {
            modelContext.insert(QuickAddCount(itemID: item.id, date: todayStart, count: 1))
        }
        persist()
    }

    private func decrement(_ item: QuickAddItem) {
        guard let existing = todayCount(for: item), existing.count > 0 else { return }
        existing.count -= 1
        persist()
    }

    private func delete(_ item: QuickAddItem) {
        // Remove the definition and all of its tallies.
        for c in allCounts where c.itemID == item.id {
            modelContext.delete(c)
        }
        modelContext.delete(item)
        persist()
    }

    private func persist() {
        try? modelContext.save()
        WidgetDataStore.saveCurrentDaySummary(modelContext: modelContext, calorieTarget: calorieTarget)
    }
}

// MARK: - Chip

private struct QuickChip: View {
    let item: QuickAddItem
    let count: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private struct Ghost: Identifiable {
        let id = UUID()
        let text: String
    }
    @State private var ghosts: [Ghost] = []

    var body: some View {
        Button {
            increment()
        } label: {
            ZStack {
                // Full-width row: [icon 40pt] [name + count·unit, stacked] [Spacer] [−] [+]
                HStack(spacing: Layout.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.accentTintBg)
                            .frame(width: 40, height: 40)
                        CalorisorIconView(icon: item.icon, size: 22)
                            .foregroundStyle(Color.accentFill)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.sofraLabel)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(count)")
                                .font(.sofraNumericSmall)
                                .foregroundStyle(Color.textPrimary)
                                .contentTransition(.numericText())
                            Text(item.unit)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Explicit undo — visible only when count > 0
                    if count > 0 {
                        Button {
                            decrement()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Color.surfaceFlat, in: Circle())
                                .accessibilityLabel(String(localized: "Azalt"))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 30, height: 30)
                        .background(Color.accentFill, in: Circle())
                        .accessibilityLabel(String(localized: "Artır"))
                }
                .padding(.horizontal, Layout.Spacing.md)
                .padding(.vertical, Layout.Spacing.sm)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                .raisedSurface(cornerRadius: Layout.Radius.card)

                ForEach(ghosts) { ghost in
                    GhostLabel(text: ghost.text)
                }
            }
        }
        .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
        .contextMenu {
            Button { onEdit() } label: { Label("Düzenle", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Sil", systemImage: "trash") }
        }
    }

    private func increment() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.sofraSpring) { onIncrement() }
        spawnGhost("+1")
    }

    private func decrement() {
        guard count > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.sofraSpring) { onDecrement() }
        spawnGhost("-1")
    }

    private func spawnGhost(_ text: String) {
        let ghost = Ghost(text: text)
        ghosts.append(ghost)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            ghosts.removeAll { $0.id == ghost.id }
        }
    }
}

/// A "+1"/"-1" that floats upward and fades out (500ms, bouncy).
/// Replaces the previous `easeOut(0.4)` with `Animation.sofraBouncy`
/// (Amo95 pattern, retuned for Sofra) — a hair of overshoot at the
/// end matches the spec's "Instagram like-count artışı hissi, ama
/// abartısız" guidance.
private struct GhostLabel: View {
    let text: String
    @State private var risen = false

    var body: some View {
        Text(text)
            .font(.sofraNumericSmall)
            .foregroundStyle(text == "+1" ? Color.accentText : Color.textMuted)
            .offset(y: risen ? -28 : 0)
            .opacity(risen ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.sofraBouncy) { risen = true }
            }
    }
}

// MARK: - Editor

struct QuickAddEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// nil → create a new item; non-nil → edit the given item.
    let item: QuickAddItem?
    let nextSortOrder: Int

    @State private var name: String = ""
    @State private var unit: String = ""
    @State private var iconName: String = CalorisorIcon.tabak.rawValue
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""

    private var isEditing: Bool { item != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let iconColumns = [GridItem(.adaptive(minimum: 52), spacing: Layout.Spacing.sm)]

    /// The numeric keypad has no system "done" key — this drives both a keyboard
    /// toolbar button and `.scrollDismissesKeyboard` below.
    private enum EditorField: Hashable {
        case name, unit, calories, protein, carbs, fat
    }
    @FocusState private var focusedField: EditorField?

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    templatesSection
                }

                Section("Sayaç") {
                    TextField("Ad (örn. Ekmek)", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Birim (örn. dilim)", text: $unit)
                        .focused($focusedField, equals: .unit)
                }

                Section {
                    nutrientRow(title: "Kalori", text: $caloriesText, unit: "kcal", field: .calories)
                    nutrientRow(title: "Protein", text: $proteinText, unit: "g", field: .protein)
                    nutrientRow(title: "Karbonhidrat", text: $carbsText, unit: "g", field: .carbs)
                    nutrientRow(title: "Yağ", text: $fatText, unit: "g", field: .fat)
                } header: {
                    Text("Birim başına besin değeri (opsiyonel)")
                } footer: {
                    Text("Hepsini 0 bırakırsan sadece adet sayılır. Değer girersen her adet günlük toplamlara ve halkaya eklenir.")
                }

                Section("İkon") {
                    LazyVGrid(columns: iconColumns, spacing: Layout.Spacing.sm) {
                        ForEach(CalorisorIcon.allCases) { icon in
                            Button {
                                iconName = icon.rawValue
                            } label: {
                                CalorisorIconView(icon: icon, size: 26)
                                    .foregroundStyle(iconName == icon.rawValue ? Color.onAccent : Color.accentFill)
                                    .frame(width: 52, height: 52)
                                    .background(
                                        iconName == icon.rawValue ? Color.accentFill : Color.accentTintBg,
                                        in: RoundedRectangle(cornerRadius: Layout.Radius.control)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Layout.Spacing.xs)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            deleteItem()
                        } label: {
                            Text("Sayacı Sil")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPage.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: isEditing ? "Sayacı Düzenle" : "Yeni Sayaç"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }.disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
        .tint(Color.accentFill)
    }

    // MARK: Templates

    private var templatesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Spacing.sm) {
                    ForEach(QuickAddTemplates.all) { template in
                        Button {
                            apply(template)
                        } label: {
                            HStack(spacing: 6) {
                                CalorisorIconView(icon: template.icon, size: 16)
                                    .foregroundStyle(Color.accentFill)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(template.name)
                                        .font(.sofraCaption)
                                        .foregroundStyle(Color.textPrimary)
                                    Text("\(Int(template.calories)) kcal")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .padding(.horizontal, Layout.Spacing.md)
                            .padding(.vertical, Layout.Spacing.sm)
                            .background(Color.accentTintBg, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        } header: {
            Text("Şablonlar")
        } footer: {
            Text("Birine dokun, değerleri otomatik dolsun — sonra dilediğin gibi düzenle.")
        }
    }

    private func nutrientRow(title: String, text: Binding<String>, unit: String, field: EditorField) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .font(.sofraNumericSmall)
                .focused($focusedField, equals: field)
            Text(unit)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: Actions

    private func apply(_ template: QuickAddTemplate) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        name = template.name
        unit = template.unit
        iconName = template.icon.rawValue
        caloriesText = format(template.calories)
        proteinText = format(template.protein)
        carbsText = format(template.carbs)
        fatText = format(template.fat)
        focusedField = nil
    }

    /// Trim ".0" so whole numbers read cleanly (e.g. "80", not "80.0").
    private func format(_ value: Double) -> String {
        value == 0 ? "" : (value == value.rounded() ? String(Int(value)) : String(value))
    }

    private func load() {
        guard let item else { return }
        name = item.name
        unit = item.unit
        iconName = item.iconName
        caloriesText = format(item.caloriesPerUnit)
        proteinText = format(item.proteinPerUnit)
        carbsText = format(item.carbsPerUnit)
        fatText = format(item.fatPerUnit)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        let calories = parse(caloriesText)
        let protein = parse(proteinText)
        let carbs = parse(carbsText)
        let fat = parse(fatText)

        if let item {
            item.name = trimmedName
            item.unit = trimmedUnit
            item.iconName = iconName
            item.caloriesPerUnit = calories
            item.proteinPerUnit = protein
            item.carbsPerUnit = carbs
            item.fatPerUnit = fat
        } else {
            modelContext.insert(QuickAddItem(
                name: trimmedName,
                unit: trimmedUnit,
                iconName: iconName,
                caloriesPerUnit: calories,
                proteinPerUnit: protein,
                carbsPerUnit: carbs,
                fatPerUnit: fat,
                sortOrder: nextSortOrder
            ))
        }
        try? modelContext.save()
        dismiss()
    }

    /// Accepts both "," and "." as the decimal separator (Turkish keyboards).
    private func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func deleteItem() {
        guard let item else { return }
        let id = item.id
        let descriptor = FetchDescriptor<QuickAddCount>()
        if let counts = try? modelContext.fetch(descriptor) {
            for c in counts where c.itemID == id { modelContext.delete(c) }
        }
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
