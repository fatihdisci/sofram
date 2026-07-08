//
//  ResultItemCard.swift
//  Sofra — single recognized item card with portion correction controls.
//

import SwiftUI

struct ResultItemCard: View {
    let item: EditableVisionItem
    let onUnitChange: (PortionUnit) -> Void
    let onQuantityChange: (Double) -> Void

    /// Editable units shown in the picker (Turkish household vocabulary only).
    private let editableUnits: [PortionUnit] = [
        .kepce, .yemekKasigi, .suBardagi, .cayBardagi,
        .dilim, .avuc, .kase, .adet
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            // Header: icon + name + confidence
            HStack(spacing: Layout.Spacing.sm) {
                SofraIconView(icon: itemIcon, size: 28)
                    .foregroundStyle(Color.accentFill)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.sofraHeading)
                        .foregroundStyle(Color.textPrimary)

                    if item.confidence < 0.6 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("Şüpheli/tahminidir")
                                .font(.sofraCaption)
                        }
                        .foregroundStyle(Color.accentText)
                    }
                }

                Spacer()

                // Confidence pill
                Text("\(Int(item.confidence * 100))%")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(confidenceColor)
                    .padding(.horizontal, Layout.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(confidenceColor.opacity(0.12), in: Capsule())
            }

            // Portion correction row
            portionCorrectionRow

            // Macros row
            macrosRow

            // Note for shared-pot items
            if let note = item.note, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                    Text(note)
                        .font(.sofraCaption)
                }
                .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    // MARK: - Portion correction

    private var portionCorrectionRow: some View {
        VStack(spacing: Layout.Spacing.sm) {
            // Unit picker — horizontal scroll of Turkish units
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Spacing.xs) {
                    ForEach(editableUnits, id: \.self) { unit in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                onUnitChange(unit)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let icon = unit.icon {
                                    SofraIconView(icon: icon, size: 14)
                                }
                                Text(unit.displayName)
                                    .font(.sofraCaption)
                            }
                            .foregroundStyle(item.householdUnit == unit
                                             ? Color.onAccent : Color.textSecondary)
                            .padding(.horizontal, Layout.Spacing.md)
                            .padding(.vertical, Layout.Spacing.xs)
                            .background(
                                item.householdUnit == unit
                                ? Color.accentFill : Color.surfaceFlat,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Quantity stepper
            HStack(spacing: Layout.Spacing.md) {
                // Decrease
                Button {
                    let step = unitStep
                    let newQty = max(unitMin, item.householdQuantity - step)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onQuantityChange(newQty)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.textPrimary)
                        .background(Color.surfaceFlat, in: Circle())
                }
                .buttonStyle(.plain)

                // Current quantity + estimated grams
                VStack(spacing: 2) {
                    Text("\(item.householdQuantity, specifier: "%.1f") \(item.householdUnit.displayName)")
                        .font(.sofraBody)
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: item.householdQuantity)
                    Text("~\(Int(item.estimatedGrams))g")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minWidth: 120)

                // Increase
                Button {
                    let step = unitStep
                    let newQty = min(unitMax, item.householdQuantity + step)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onQuantityChange(newQty)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.onAccent)
                        .background(Color.accentFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Macros

    private var macrosRow: some View {
        HStack(spacing: Layout.Spacing.lg) {
            Spacer()
            macroPill(label: "kcal", value: item.calories, color: .accentText)
            macroPill(label: "protein", value: item.proteinG, color: .macroProtein)
            macroPill(label: "carbs", value: item.carbsG, color: .macroCarb)
            macroPill(label: "yağ", value: item.fatG, color: .macroFat)
            Spacer()
        }
        .padding(.top, Layout.Spacing.xs)
    }

    private func macroPill(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(.sofraNumericSmall)
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, Layout.Spacing.sm)
        .padding(.vertical, Layout.Spacing.xs)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private var itemIcon: SofraIcon {
        item.householdUnit.icon ?? .tabak
    }

    private var confidenceColor: Color {
        item.confidence >= 0.75 ? .green : (item.confidence >= 0.5 ? .orange : .red)
    }

    private var unitStep: Double {
        switch item.householdUnit {
        case .adet: return 1
        case .dilim: return 1
        default: return 0.5
        }
    }

    private var unitMin: Double {
        switch item.householdUnit {
        case .adet: return 1
        case .dilim: return 0.5
        default: return 0.5
        }
    }

    private var unitMax: Double { 20 }
}
