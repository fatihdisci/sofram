//
//  QuickCounterView.swift
//  Sofra — customizable quick-add counters.
//
//  Users define their own counters (name / unit / icon / optional calories),
//  reorder them, and tally them per day. Replaces the hardcoded bread/tea pair.
//
//  Per mikro-etkilesimler.md:
//  - Each tap: .impact(light) haptic + "+1" ghost text fades upward (400ms)
//  - No shaming/warning for high counts — neutral data only.
//  - Long-press decrements (mis-tap recovery), medium haptic + "-1" ghost.
//

import SwiftUI
import SwiftData
import WidgetKit

struct QuickCounterView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \QuickAddItem.sortOrder) private var items: [QuickAddItem]
    @Query private var allCounts: [QuickAddCount]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000

    @State private var editingItem: QuickAddItem?
    @State private var showEditor = false

    private let columns = [
        GridItem(.flexible(), spacing: Layout.Spacing.md),
        GridItem(.flexible(), spacing: Layout.Spacing.md)
    ]

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
                LazyVGrid(columns: columns, spacing: Layout.Spacing.md) {
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
        ZStack {
            HStack(spacing: Layout.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.accentTintBg)
                        .frame(width: 44, height: 44)
                    SofraIconView(icon: item.icon, size: 24)
                        .foregroundStyle(Color.accentFill)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(count)")
                            .font(.sofraNumericSmall)
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                        Text(item.unit)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentFill)
            }
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, Layout.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)

            ForEach(ghosts) { ghost in
                GhostLabel(text: ghost.text)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Layout.Radius.card))
        .onTapGesture { increment() }
        .onLongPressGesture(minimumDuration: 0.4) { decrement() }
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

/// A "+1"/"-1" that floats upward and fades out (400ms, ease-out).
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
                withAnimation(.easeOut(duration: 0.4)) { risen = true }
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
    @State private var iconName: String = SofraIcon.tabak.rawValue
    @State private var caloriesText: String = ""

    private var isEditing: Bool { item != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let iconColumns = [GridItem(.adaptive(minimum: 52), spacing: Layout.Spacing.sm)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sayaç") {
                    TextField("Ad (örn. Ekmek)", text: $name)
                    TextField("Birim (örn. dilim)", text: $unit)
                }

                Section {
                    HStack {
                        TextField("0", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                        Text("kcal / birim")
                            .font(.sofraCaption)
                            .foregroundStyle(Color.textMuted)
                    }
                } header: {
                    Text("Kalori (opsiyonel)")
                } footer: {
                    Text("0 bırakırsan sadece adet sayılır, kaloriye eklenmez. Bir değer girersen her adet günlük kaloriye ve halkaya eklenir.")
                }

                Section("İkon") {
                    LazyVGrid(columns: iconColumns, spacing: Layout.Spacing.sm) {
                        ForEach(SofraIcon.allCases) { icon in
                            Button {
                                iconName = icon.rawValue
                            } label: {
                                SofraIconView(icon: icon, size: 26)
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
            .navigationTitle(isEditing ? "Sayacı Düzenle" : "Yeni Sayaç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
        .tint(Color.accentFill)
    }

    private func load() {
        guard let item else { return }
        name = item.name
        unit = item.unit
        iconName = item.iconName
        caloriesText = item.caloriesPerUnit > 0 ? String(Int(item.caloriesPerUnit)) : ""
    }

    private func save() {
        let calories = Double(caloriesText) ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)

        if let item {
            item.name = trimmedName
            item.unit = trimmedUnit
            item.iconName = iconName
            item.caloriesPerUnit = calories
        } else {
            modelContext.insert(QuickAddItem(
                name: trimmedName,
                unit: trimmedUnit,
                iconName: iconName,
                caloriesPerUnit: calories,
                sortOrder: nextSortOrder
            ))
        }
        try? modelContext.save()
        dismiss()
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
