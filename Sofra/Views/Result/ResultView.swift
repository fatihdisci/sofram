//
//  ResultView.swift
//  Sofra — AI result screen with Turkish portion correction UI.
//
//  Each recognized item can be edited: household unit (Turkish vocabulary only),
//  quantity (stepper), calories/macros shown. Low-confidence items are flagged.
//  "Logla" saves to SwiftData and transitions to the daily ring.
//

import SwiftUI
import SwiftData

struct ResultView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    let uiImage: UIImage
    let items: [VisionItem]
    let source: ScanSource

    /// Editable copies of each item (index-matched to `items`).
    @State private var editableItems: [EditableVisionItem]
    @State private var isSaving = false

    init(uiImage: UIImage, items: [VisionItem], source: ScanSource = .photo) {
        self.uiImage = uiImage
        self.items = items
        self.source = source
        _editableItems = State(initialValue: items.map { EditableVisionItem(from: $0) })
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with captured image thumbnail
                headerView

                if items.isEmpty {
                    emptyResultView
                } else {
                    // Scrollable item cards
                    ScrollView(showsIndicators: false) {
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
                        .padding(.bottom, 120)
                    }
                }

                Spacer()

                // Bottom log button
                if !items.isEmpty {
                    bottomBar
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Layout.Spacing.md) {
            // Back to camera
            Button {
                nav.goToCamera()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .padding(Layout.Spacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }

            // Mini captured image thumbnail
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.control))

            VStack(alignment: .leading, spacing: 2) {
                Text("Sonuçlar")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)
                Text("\(items.count) öğe tanındı")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, 60)
        .padding(.bottom, Layout.Spacing.sm)
    }

    // MARK: - Empty result

    private var emptyResultView: some View {
        VStack(spacing: Layout.Spacing.xl) {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.textMuted)
            Text("Fotoğrafta yemek bulunamadı.")
                .font(.sofraHeading)
                .foregroundStyle(Color.textPrimary)
            Text("Farklı bir açıyla tekrar deneyin.")
                .font(.sofraBody)
                .foregroundStyle(Color.textSecondary)
            Button("Tekrar çek") {
                nav.goToCamera()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentFill)
            Spacer()
        }
        .padding()
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Layout.Spacing.xs) {
            LogButton {
                await save()
            } onComplete: {
                nav.goToDaily()
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.bottom, 40)
        .padding(.top, Layout.Spacing.md)
        .background(
            Color.bgPage
                .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
        )
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
    }
}

// MARK: - Editable copy

@Observable
final class EditableVisionItem {
    var name: String
    var nameEn: String
    var estimatedGrams: Double
    var householdUnit: PortionUnit
    var householdQuantity: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var confidence: Double
    var note: String?

    init(from item: VisionItem) {
        self.name = item.name
        self.nameEn = item.nameEn
        self.estimatedGrams = item.estimatedGrams
        self.householdUnit = item.portionUnit
        self.householdQuantity = item.householdQuantity
        self.calories = item.calories
        self.proteinG = item.proteinG
        self.carbsG = item.carbsG
        self.fatG = item.fatG
        self.confidence = item.confidence
        self.note = item.note
    }

    var portionUnit: PortionUnit { householdUnit }
}
