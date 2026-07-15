//
//  ResultView.swift
//  Calp — AI result screen with Turkish portion correction UI.
//
//  Each recognized item can be edited: household unit (Turkish vocabulary only),
//  quantity (stepper), calories/macros shown. Low-confidence items are flagged.
//  Nutrition scales with the corrected quantity (the AI estimate is treated as
//  per-portion density). A live totals bar sits above "Kaydet", which saves to
//  SwiftData and transitions to the daily ring.
//

import SwiftUI
import SwiftData
import WidgetKit

struct ResultView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    let uiImage: UIImage
    let items: [VisionItem]
    let source: ScanSource
    let rawJSON: String

    /// Editable copies of each item (index-matched to `items`).
    @State private var editableItems: [EditableVisionItem]
    @State private var isSaving = false
    @State private var cardsVisible = false
    @State private var hasEdits = false
    @State private var showsDiscardConfirmation = false

    init(uiImage: UIImage, items: [VisionItem], source: ScanSource = .photo, rawJSON: String,
         foodReferences: [FoodReference] = TurkishFoodReference.foods()) {
        self.uiImage = uiImage
        self.items = items
        self.source = source
        self.rawJSON = rawJSON
        _editableItems = State(initialValue: items.map { EditableVisionItem(from: $0, references: foodReferences) })
    }

    private var totalCalories: Double { editableItems.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { editableItems.reduce(0) { $0 + $1.proteinG } }
    private var totalCarbs: Double { editableItems.reduce(0) { $0 + $1.carbsG } }
    private var totalFat: Double { editableItems.reduce(0) { $0 + $1.fatG } }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with captured image thumbnail
                headerView

                if editableItems.isEmpty {
                    emptyResultView
                } else {
                    // Scrollable item cards — spring from bottom (catalog)
                    ScrollView(showsIndicators: false) {
                        if cardsVisible {
                            VStack(spacing: Layout.Spacing.md) {
                                ForEach(editableItems) { item in
                                    ResultItemCard(
                                        item: item,
                                        showsMacros: editableItems.count > 1,
                                        onUnitChange: { newUnit in
                                            guard item.householdUnit != newUnit else { return }
                                            item.householdUnit = newUnit
                                            hasEdits = true
                                        },
                                        onQuantityChange: { newQty in
                                            guard item.householdQuantity != newQty else { return }
                                            item.householdQuantity = newQty
                                            hasEdits = true
                                        },
                                        onNameChange: { newName in
                                            guard item.name != newName else { return }
                                            item.rename(to: newName)
                                            hasEdits = true
                                        },
                                        onDelete: {
                                            deleteItem(id: item.id)
                                        }
                                    )
                                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, Layout.Spacing.lg)
                            .padding(.top, Layout.Spacing.md)
                            .padding(.bottom, 160)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }

            // Bottom bar overlays the scroll content
            if !editableItems.isEmpty {
                VStack {
                    Spacer()
                    bottomBar
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                cardsVisible = true
            }
        }
        .confirmationDialog(
            "Düzenlemeler kaydedilmedi",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Çıkış", role: .destructive) {
                nav.dismissResult(source: source)
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Layout.Spacing.md) {
            // Dismiss — photo scans return to the camera, text scans to the editor
            Button {
                requestDismiss()
            } label: {
                Image(systemName: source == .text ? "chevron.left" : "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.surfaceRaised, in: Circle())
                    .raisedSurface(cornerRadius: 21)
                    .accessibilityLabel(String(localized: "Kapat"))
            }

            // Mini captured image thumbnail (photo scans only)
            if source == .photo {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.control))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sonuçlar")
                    .font(.calpHeading)
                    .foregroundStyle(Color.textPrimary)
                Text(editableItems.count == 1 ? "1 öğe tanındı" : "\(editableItems.count) öğe tanındı")
                    .font(.calpCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
        .padding(.bottom, Layout.Spacing.sm)
    }

    // MARK: - Empty result

    private var emptyResultView: some View {
        VStack(spacing: Layout.Spacing.lg) {
            Spacer()
            CalpIconView(icon: .emptyPlate, size: 56)
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
            Text(source == .text ? "Yazdıklarından yemek çıkaramadık." : "Fotoğrafta yemek bulunamadı.")
                .font(.calpHeading)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(source == .text ? "Biraz daha ayrıntı ekleyip tekrar dene." : "Farklı bir açıyla tekrar deneyin.")
                .font(.calpBody)
                .foregroundStyle(Color.textSecondary)
            Button {
                requestDismiss()
            } label: {
                Text(source == .text ? "Düzenle" : "Tekrar çek")
                    .font(.calpLabel)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.xl)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: Capsule())
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Layout.Spacing.sm) {
            HStack(spacing: Layout.Spacing.sm) {
                Text("Toplam")
                    .font(.calpCaption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                totalValue(totalCalories, label: "kcal", emphasized: true)
                totalValue(totalProtein, label: "protein")
                totalValue(totalCarbs, label: "karb.")
                totalValue(totalFat, label: "yağ")
            }
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, Layout.Spacing.sm)
            .background(Color.surfaceRaised, in: Capsule())

            LogButton {
                await save()
            } onComplete: {
                nav.goToDaily()
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.bottom, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
        .background(
            LinearGradient(colors: [Color.bgPage.opacity(0), Color.bgPage],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -Layout.Spacing.xl)
        )
    }

    private func totalValue(_ value: Double, label: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(.calpNumericSmall)
                .foregroundStyle(emphasized ? Color.accentText : Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.calpSpring, value: value)
            Text(label)
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Save

    private func save() async {
        let entry = ScanEntry(source: source, rawAIResponse: rawJSON)
        let loggedItems = editableItems.map { item in
            let logged = LoggedItem(
                name: item.name,
                nameEn: item.nameEn,
                portionUnit: item.portionUnit,
                quantity: item.householdQuantity,
                estimatedGrams: item.estimatedGrams,
                calories: item.calories,
                protein: item.proteinG,
                carbs: item.carbsG,
                fat: item.fatG,
                confidence: item.confidence,
                note: item.note,
                valueSource: item.valueSource
            )
            logged.scanEntry = entry
            return logged
        }
        entry.items = loggedItems
        modelContext.insert(entry)
        try? modelContext.save()

        let totals = loggedItems.reduce(into: (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0)) { totals, item in
            totals.calories += item.calories
            totals.protein += item.protein
            totals.carbs += item.carbs
            totals.fat += item.fat
        }
        _ = await HealthKitManager.shared.syncMealNutrition(
            externalID: entry.id,
            date: entry.timestamp,
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat
        )

        // A logged text entry consumes its draft
        if source == .text {
            nav.textLogDraft = ""
        }

        // Update widget with new totals
        let target = UserDefaults.standard.object(forKey: "calp.dailyCalorieTarget") as? Double ?? 2000
        WidgetDataStore.saveCurrentDaySummary(
            modelContext: modelContext,
            calorieTarget: target
        )

        // Logging covers a meal — re-arm so that meal's reminder (and the
        // no-log nudge) drop for today (SF-EX06/07).
        MealReminderService.shared.reschedule(modelContext: modelContext)
    }

    private func deleteItem(id: UUID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.calpSpring) {
            editableItems.removeAll { $0.id == id }
            hasEdits = true
        }
    }

    private func requestDismiss() {
        if hasEdits {
            showsDiscardConfirmation = true
        } else {
            nav.dismissResult(source: source)
        }
    }
}

// MARK: - Editable copy

/// Editable copy of a `VisionItem`. The AI's estimate is kept as a per-unit
/// baseline; corrected quantities scale calories, macros and grams from it —
/// changing "2 kepçe" to "4 kepçe" doubles the item's nutrition.
@Observable
final class EditableVisionItem: Identifiable {
    let id = UUID()
    var name: String
    var nameEn: String
    var householdUnit: PortionUnit {
        didSet {
            guard householdUnit != oldValue else { return }
            selectedUnitWasChanged = true
            gramsPerSelectedUnit = gramsPerUnit(for: householdUnit)
        }
    }
    var householdQuantity: Double
    var confidence: Double
    var note: String?

    /// Where calories/macros came from — "reference" (deterministic DB match)
    /// or "ai" (kept the model's own estimate). Drives the Sonuçlar badge.
    private(set) var valueSource: String
    private(set) var confidenceNote: String?
    private(set) var referenceName: String?

    /// The reconciled estimate (reference values when matched, otherwise the
    /// AI's own numbers) — baseline for scaling as quantity is corrected.
    private let baseQuantity: Double
    private let baseGrams: Double
    private var baseCalories: Double
    private var baseProtein: Double
    private var baseCarbs: Double
    private var baseFat: Double
    private var matchedReference: FoodReference?
    private var gramsPerSelectedUnit: Double?
    private var selectedUnitWasChanged = false
    private let references: [FoodReference]
    private let originalAICalories: Double
    private let originalAIProtein: Double
    private let originalAICarbs: Double
    private let originalAIFat: Double

    init(from item: VisionItem, references: [FoodReference] = []) {
        let reconciled = ReferenceReconciler.reconcile(item: item, in: references)

        self.name = item.name
        self.nameEn = item.nameEn
        self.householdUnit = item.portionUnit
        self.householdQuantity = item.householdQuantity
        self.confidence = item.confidence
        self.note = item.note
        self.valueSource = reconciled.source.rawValue
        self.confidenceNote = reconciled.confidenceNote
        self.referenceName = reconciled.referenceName
        self.baseQuantity = max(item.householdQuantity, 0.001)
        self.baseGrams = item.estimatedGrams
        self.baseCalories = reconciled.calories
        self.baseProtein = reconciled.protein
        self.baseCarbs = reconciled.carbs
        self.baseFat = reconciled.fat
        self.matchedReference = references.first { $0.name == reconciled.referenceName }
        self.gramsPerSelectedUnit = nil
        self.references = references
        self.originalAICalories = item.calories
        self.originalAIProtein = item.proteinG
        self.originalAICarbs = item.carbsG
        self.originalAIFat = item.fatG
    }

    private var scale: Double { householdQuantity / baseQuantity }
    private var calorieDensity: Double { baseCalories / max(baseGrams, 1) }
    private var proteinDensity: Double { baseProtein / max(baseGrams, 1) }
    private var carbsDensity: Double { baseCarbs / max(baseGrams, 1) }
    private var fatDensity: Double { baseFat / max(baseGrams, 1) }

    var estimatedGrams: Double {
        if let gramsPerSelectedUnit {
            return householdQuantity * gramsPerSelectedUnit
        }
        return baseGrams * scale
    }

    var calories: Double { calorieDensity * estimatedGrams }
    var proteinG: Double { proteinDensity * estimatedGrams }
    var carbsG: Double { carbsDensity * estimatedGrams }
    var fatG: Double { fatDensity * estimatedGrams }

    var portionUnit: PortionUnit { householdUnit }

    func rename(to newName: String) {
        let cleanedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let candidate = VisionItem(
            name: cleanedName,
            nameEn: nameEn,
            estimatedGrams: baseGrams,
            householdUnit: householdUnit.rawValue,
            householdQuantity: baseQuantity,
            calories: originalAICalories,
            proteinG: originalAIProtein,
            carbsG: originalAICarbs,
            fatG: originalAIFat,
            confidence: confidence,
            note: note
        )
        let reconciled = ReferenceReconciler.reconcile(item: candidate, in: references)

        name = cleanedName
        valueSource = reconciled.source.rawValue
        confidenceNote = reconciled.confidenceNote
        referenceName = reconciled.referenceName
        baseCalories = reconciled.calories
        baseProtein = reconciled.protein
        baseCarbs = reconciled.carbs
        baseFat = reconciled.fat
        matchedReference = references.first { $0.name == reconciled.referenceName }

        if matchedReference != nil {
            gramsPerSelectedUnit = gramsPerUnit(for: householdUnit)
        } else {
            gramsPerSelectedUnit = selectedUnitWasChanged
                ? NutritionConstants.defaultGrams(for: householdUnit)
                : nil
        }
    }

    private func gramsPerUnit(for unit: PortionUnit) -> Double? {
        if let referencePortion = referencePortion(for: unit) {
            return referencePortion.grams / max(referencePortion.householdQuantity, 0.001)
        }
        return NutritionConstants.defaultGrams(for: unit)
    }

    private func referencePortion(for unit: PortionUnit) -> RefPortion? {
        guard let matchedReference else { return nil }
        return ([matchedReference.typicalPortion] + matchedReference.alternatePortions)
            .first { $0.householdUnit == unit.rawValue }
    }
}
