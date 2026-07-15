//
//  LogButton.swift
//  Calp — animated "Kaydet" button with checkmark morph + celebration spray.
//
//  Per mikro-etkilesimler.md:
//  - scale(0.96) + .impact(medium) on tap
//  - SF Symbol content-transition to checkmark, 400ms hold
//  - onComplete fires after the 400ms hold so the parent can navigate
//
//  Pow (EmergeTools) integration:
//  - `.feedback(hapticImpact:)` replaces the manual `UIImpactFeedbackGenerator`
//    call — driven by `triggerID` so it re-fires on every tap regardless of
//    `isAnimating` state (the previous manual call only fired once because
//    `isAnimating` was never reset).
//  - `.spray` emits a one-shot burst of small checkmarks from the button
//    center on every successful log — a celebration moment that the previous
//    implementation didn't have. Net-new behavior, not a replacement.
//  - `.particleLayer(name:)` wraps the button so the spray particles render
//    on a separate layer and don't get clipped by the button's rounded rect
//    or its pressed-state overlay.
//
//  Pow is intentionally scoped to the haptic + the celebration only; the
//  morph timing (200ms → 300ms → 400ms hold) stays in our Task because Pow
//  doesn't have an opinion on chained sequential state changes.
//

import SwiftUI
import Pow

struct LogButton: View {
    let action: () async -> Void
    var onComplete: (() -> Void)?

    /// Increments on every successful tap. Drives Pow's `.changeEffect` so
    /// the haptic + particle burst fire deterministically per tap (not gated
    /// by a one-way `isAnimating` boolean).
    @State private var triggerID = UUID()

    @State private var isAnimating = false
    @State private var showCheckmark = false

    var body: some View {
        Button {
            guard !isAnimating else { return }
            Task {
                triggerID = UUID()   // fires Pow: haptic + spray
                // Scale down + haptic (Pow handles the impact; the visual scale is ours)
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isAnimating = true
                }
                // Morph to checkmark after 200ms
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCheckmark = true
                }
                // Perform the save action
                await action()
                // Hold 400ms then signal completion
                try? await Task.sleep(nanoseconds: 400_000_000)
                onComplete?()
            }
        } label: {
            HStack(spacing: Layout.Spacing.sm) {
                if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 16))
                }
                Text("Kaydet")
                    .font(.calpLabel)
            }
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, Layout.Spacing.xl)
            .padding(.vertical, Layout.Spacing.md)
            .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
        }
        .scaleEffect(isAnimating ? 0.96 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isAnimating)
        // Pow: impact haptic on every tap. `triggerID` changes → effect fires.
        .changeEffect(.feedback(hapticImpact: .medium), value: triggerID)
        // Pow: one-shot checkmark particle burst on every successful log.
        // `onAccent` so the particles read as part of the button's accent family.
        .changeEffect(
            .spray(origin: .center) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onAccent)
            },
            value: triggerID
        )
        // Pow: declare the particle layer here so the spray doesn't get
        // clipped by the button's rounded background or its pressed overlay.
        .particleLayer(name: "logButtonSpray")
    }
}
