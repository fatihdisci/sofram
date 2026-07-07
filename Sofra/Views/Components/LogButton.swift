//
//  LogButton.swift
//  Sofra — animated "Logla" button with checkmark morph.
//
//  Per mikro-etkilesimler.md:
//  - scale(0.96) + .impact(medium) on tap
//  - SF Symbol content-transition to checkmark, 400ms hold
//  - onComplete fires after the 400ms hold so the parent can navigate
//

import SwiftUI

struct LogButton: View {
    let action: () async -> Void
    var onComplete: (() -> Void)?

    @State private var isAnimating = false
    @State private var showCheckmark = false

    var body: some View {
        Button {
            guard !isAnimating else { return }
            Task {
                // Scale down + haptic
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
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
                Text("Logla")
                    .font(.sofraLabel)
            }
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, Layout.Spacing.xl)
            .padding(.vertical, Layout.Spacing.md)
            .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
        }
        .scaleEffect(isAnimating ? 0.96 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isAnimating)
    }
}
