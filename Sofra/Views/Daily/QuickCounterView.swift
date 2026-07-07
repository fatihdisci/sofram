//
//  QuickCounterView.swift
//  Sofra — bread & tea compact quick counters.
//
//  Per mikro-etkilesimler.md:
//  - Each tap: .impact(light) haptic + "+1" ghost text fades upward (400ms)
//  - No shaming/warning for high counts — neutral data only.
//  - Long-press decrements (mis-tap recovery), medium haptic + "-1" ghost.
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
                unit: "dilim",
                count: $breadSlices
            )
            CounterPill(
                icon: .cayBardagi,
                label: "Çay",
                unit: "bardak",
                count: $teaGlasses
            )
        }
    }
}

struct CounterPill: View {
    let icon: SofraIcon
    let label: String
    let unit: String
    @Binding var count: Int

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
                    SofraIconView(icon: icon, size: 24)
                        .foregroundStyle(Color.accentFill)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(count)")
                            .font(.sofraNumericSmall)
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                    }
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentFill)
            }
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, Layout.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)

            // Ghost "+1"/"-1" texts floating up
            ForEach(ghosts) { ghost in
                GhostLabel(text: ghost.text)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Layout.Radius.card))
        .onTapGesture { increment() }
        .onLongPressGesture(minimumDuration: 0.4) { decrement() }
    }

    private func increment() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.sofraSpring) { count += 1 }
        spawnGhost("+1")
    }

    private func decrement() {
        guard count > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.sofraSpring) { count -= 1 }
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

/// A "+1"/"-1" that floats upward and fades out (400ms, ease-out — spring
/// overshoot would bounce the text back down, visually wrong here).
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
