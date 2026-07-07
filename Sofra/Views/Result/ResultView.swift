//
//  ResultView.swift
//  Sofra — AI result screen with Turkish portion correction UI.
//
//  Each recognized item can be edited: household unit (Turkish vocabulary only),
//  quantity (stepper), calories/macros shown. Low-confidence items are flagged.
//  Nutrition scales with the corrected quantity (the AI estimate is treated as
//  per-portion density). A live totals bar sits above "Logla", which saves to
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

    /// Editable copies of each item (index-matched to `items`).
    @State private var editableItems: [EditableVisionItem]
    @State private var isSaving = false
    @State private var cardsVisible = false

    init(uiImage: UIImage, items: [VisionItem], source: ScanSource = .photo) {
        self.uiImage = uiImage
        self.items = items
        self.source = source
        _editableItems = State(initialValue: items.map { EditableVisionItem(from: $0) })
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

                if items.isEmpty {
                    emptyResultView
                } else {
                    // Scrollable item cards — spring from bottom (catalog)
                    ScrollView(showsIndicators: false) {
                        if cardsVisible {
                            VStack(spacing: Layout.Spacing.md) {
                                ForEach(Array(editableItems.enumerated()), id: \.offset) { idx, item in
                                    ResultItemCard(
                                        item: item,
                                        onUnitChange: { newUnit in
                                            editableItems[idx].householdUnit = newUnit
                                        },
                                        onQuantityChange: { newQty in
                                            editableItems[idx].householdQuantity = newQty
                                        }
                                    )
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
            if !items.isEmpty {
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
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Layout.Spacing.md) {
            // Dismiss — photo scans return to the camera, text scans to the editor
            Button {
                nav.dismissResult(source: source)
            } label: {
                Image(systemName: source == .text ? "chevron.left" : "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.surfaceRaised, in: Circle())
                    .raisedSurface(cornerRadius: 21)
            }

            // Mini captured image thumbnail (photo scans only)
            if source == .photo {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.control))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sonuçlar")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)
                Text(items.count == 1 ? "1 öğe tanındı" : "\(items.count) öğe tanındı")
                    .font(.sofraCaption)
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
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)
            Text(source == .text ? "Yazdıklarından yemek çıkaramadık." : "Fotoğrafta yemek bulunamadı.")
                .font(.sofraHeading)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(source == .text ? "Biraz daha ayrıntı ekleyip tekrar dene." : "Farklı bir açıyla tekrar deneyin.")
                .font(.sofraBody)
                .foregroundStyle(Color.textSecondary)
            Button {
                nav.dismissResult(source: source)
            } label: {
                Text(source == .text ? "Düzenle" : "Tekrar çek")
                    .font(.sofraLabel)
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
        VStack(spacing: Layout.Spacing.md) {
            // Live totals — update as portions are corrected
            HStack(spacing: 0) {
                totalCell(value: totalCalories, label: "kcal", emphasized: true)
                totalCell(value: totalProtein, label: "protein")
                totalCell(value: totalCarbs, label: "karb.")
                totalCell(value: totalFat, label: "yağ")
            }
            .padding(.vertical, Layout.Spacing.sm)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)

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

    private func totalCell(value: Double, label: String, emphasized: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(.sofraNumericSmall)
                .foregroundStyle(emphasized ? Color.accentText : Color.textPrimary)
                .contentTransition(.numericText())
                .animation(.sofraSpring, value: value)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save

    private func save() async {
        let entry = ScanEntry(source: source)
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
                note: item.note
            )
            logged.scanEntry = entry
            return logged
        }
        entry.items = loggedItems
        modelContext.insert(entry)
        try? modelContext.save()
        FreeScanCounter.shared.recordScan()

        // A logged text entry consumes its draft
        if source == .text {
            nav.textLogDraft = ""
        }

        // Update widget with new totals
        let target = UserDefaults.standard.object(forKey: "sofra.dailyCalorieTarget") as? Double ?? 2000
        WidgetDataStore.saveCurrentDaySummary(
            modelContext: modelContext,
            calorieTarget: target
        )
    }
}

// MARK: - Editable copy

/// Editable copy of a `VisionItem`. The AI's estimate is kept as a per-unit
/// baseline; corrected quantities scale calories, macros and grams from it —
/// changing "2 kepçe" to "4 kepçe" doubles the item's nutrition.
@Observable
final class EditableVisionItem {
    var name: String
    var nameEn: String
    var householdUnit: PortionUnit
    var householdQuantity: Double
    var confidence: Double
    var note: String?

    /// The AI's original estimate (baseline for scaling).
    private let baseQuantity: Double
    private let baseGrams: Double
    private let baseCalories: Double
    private let baseProtein: Double
    private let baseCarbs: Double
    private let baseFat: Double

    init(from item: VisionItem) {
        self.name = item.name
        self.nameEn = item.nameEn
        self.householdUnit = item.portionUnit
        self.householdQuantity = item.householdQuantity
        self.confidence = item.confidence
        self.note = item.note
        self.baseQuantity = max(item.householdQuantity, 0.001)
        self.baseGrams = item.estimatedGrams
        self.baseCalories = item.calories
        self.baseProtein = item.proteinG
        self.baseCarbs = item.carbsG
        self.baseFat = item.fatG
    }

    private var scale: Double { householdQuantity / baseQuantity }

    var estimatedGrams: Double { baseGrams * scale }
    var calories: Double { baseCalories * scale }
    var proteinG: Double { baseProtein * scale }
    var carbsG: Double { baseCarbs * scale }
    var fatG: Double { baseFat * scale }

    var portionUnit: PortionUnit { householdUnit }
}
