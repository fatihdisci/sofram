//
//  ResultItemCard.swift
//  Sofra — single recognized item card with portion correction controls.
//

import SwiftUI

struct ResultItemCard: View {
    let item: EditableVisionItem
    let onUnitChange: (PortionUnit) -> Void
    let onQuantityChange: (Double) -> Void
    let onNameChange: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @FocusState private var isNameFieldFocused: Bool

    /// Editable units shown in the picker (Turkish household vocabulary only).
    private let editableUnits: [PortionUnit] = [
        .kepce, .yemekKasigi, .suBardagi, .cayBardagi,
        .dilim, .avuc, .kase, .adet
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            // Header: name + a single status badge (verified match, or a
            // low-confidence flag — never both, never a separate row each).
            HStack(alignment: .top, spacing: Layout.Spacing.sm) {
                if isEditingName {
                    TextField("Yemek adı", text: $nameDraft)
                        .font(.sofraHeading)
                        .foregroundStyle(Color.textPrimary)
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                        .onChange(of: isNameFieldFocused) { _, focused in
                            if !focused {
                                commitName()
                            }
                        }
                } else {
                    Button {
                        nameDraft = item.name
                        isEditingName = true
                        isNameFieldFocused = true
                    } label: {
                        Text(item.name)
                            .font(.sofraHeading)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Yemek adını düzenler")
                }

                Spacer()

                HStack(spacing: Layout.Spacing.xs) {
                    statusBadge

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Öğeyi sil")
                }
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
            // Unit picker — horizontal scroll of Turkish units. Faded trailing
            // edge signals there's more to scroll to (previously clipped with
            // no affordance at all, reading as a layout bug).
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
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

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
        HStack(spacing: Layout.Spacing.sm) {
            macroText(value: item.calories, label: "kcal", color: Color.accentText)
            macroDot
            macroText(value: item.proteinG, label: "protein", color: Color.macroProtein)
            macroDot
            macroText(value: item.carbsG, label: "karb.", color: Color.macroCarb)
            macroDot
            macroText(value: item.fatG, label: "yağ", color: Color.macroFat)
        }
        .padding(.top, Layout.Spacing.xs)
    }

    private var macroDot: some View {
        Circle()
            .fill(Color.textMuted.opacity(0.3))
            .frame(width: 3, height: 3)
    }

    private func macroText(value: Double, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(Int(value))")
                .font(.sofraNumericSmall)
                .foregroundStyle(color)
            Text(label)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Status badge

    /// One badge slot: a reference-matched item is "verified" (deterministic
    /// numbers, not a guess); otherwise a low-confidence AI guess is flagged.
    /// A confident AI guess (the common case) shows no badge at all.
    @ViewBuilder
    private var statusBadge: some View {
        if item.valueSource == "reference" {
            badge(icon: "checkmark.seal.fill", text: "Doğrulanmış")
        } else if item.confidence < 0.6 {
            badge(icon: "exclamationmark.triangle.fill", text: "Emin değilim")
        }
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.sofraCaption)
        }
        .foregroundStyle(Color.accentText)
        .padding(.horizontal, Layout.Spacing.sm)
        .padding(.vertical, 2)
        .background(Color.accentText.opacity(0.12), in: Capsule())
    }

    // MARK: - Helpers

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

    private func commitName() {
        guard isEditingName else { return }
        let cleanedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedName.isEmpty {
            onNameChange(cleanedName)
        }
        isEditingName = false
        isNameFieldFocused = false
    }
}
