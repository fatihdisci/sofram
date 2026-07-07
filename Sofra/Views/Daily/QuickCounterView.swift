//
//  QuickCounterView.swift
//  Sofra — bread & tea compact quick counters.
//
//  Per mikro-etkilesimler.md:
//  - Each tap: .impact(light) haptic + "+1" ghost text fades upward (400ms)
//  - No shaming/warning for high counts — neutral data only.
//

import SwiftUI

struct QuickCounterView: View {
    @Binding var breadSlices: Int
    @Binding var teaGlasses: Int

    var body: some View {
        HStack(spacing: Layout.Spacing.md) {
            CounterPill(
                icon: .ekmekDilimi,
                label: "Ekmek",
                count: breadSlices,
                onTap: { breadSlices += 1 }
            )
            CounterPill(
                icon: .cayBardagi,
                label: "Çay",
                count: teaGlasses,
                onTap: { teaGlasses += 1 }
            )
        }
    }
}

struct CounterPill: View {
    let icon: SofraIcon
    let label: String
    let count: Int
    let onTap: () -> Void

    @State private var ghostOffsets: [CGFloat] = []
    @State private var ghostOpacities: [Double] = []

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            // Add ghost text
            let idx = ghostOffsets.count
            ghostOffsets.append(0)
            ghostOpacities.append(1)
            withAnimation(.easeOut(duration: 0.4)) {
                if idx < ghostOffsets.count {
                    ghostOffsets[idx] = -24
                    ghostOpacities[idx] = 0
                }
            }
            // Clean up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !ghostOffsets.isEmpty {
                    ghostOffsets.removeFirst()
                    ghostOpacities.removeFirst()
                }
            }

            onTap()
        } label: {
            ZStack {
                HStack(spacing: Layout.Spacing.sm) {
                    SofraIconView(icon: icon, size: 22)
                        .foregroundStyle(Color.accentFill)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(label)
                            .font(.sofraCaption)
                            .foregroundStyle(Color.textSecondary)
                        Text("\(count)")
                            .font(.sofraNumericSmall)
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                    }

                    Spacer()
                }
                .padding(.horizontal, Layout.Spacing.md)
                .padding(.vertical, Layout.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))

                // Ghost "+1" texts
                ForEach(Array(ghostOffsets.enumerated()), id: \.offset) { idx, offset in
                    Text("+1")
                        .font(.sofraNumericSmall)
                        .foregroundStyle(Color.accentText)
                        .offset(y: offset)
                        .opacity(ghostOpacities[safe: idx] ?? 0)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
