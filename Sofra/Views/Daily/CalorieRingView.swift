//
//  CalorieRingView.swift
//  Sofra — central daily calorie ring with animated arc.
//
//  Per mikro-etkilesimler.md: single smooth arc animation (ease-out, 500ms)
//  to the new value — never an incrementing counter, never a hard jump.
//  Number displayed in the Geist Mono hero-display token.
//
//  Over-target is shown as neutral data ("+126 hedef üstü"), never as a
//  red/shaming state — consistent with the quick-counter philosophy.
//

import SwiftUI

struct CalorieRingView: View {
    let consumed: Double    // calories consumed so far
    let target: Double      // daily target (default if no profile)

    @State private var animatedProgress: Double = 0

    private let ringSize: CGFloat = 220
    private let stroke: CGFloat = 18
    private let inset: CGFloat = 22

    /// Radius the stroke path is centered on (used to place the end-cap bead).
    private var pathRadius: CGFloat { (ringSize - 2 * inset) / 2 }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.0)
    }

    private var remaining: Double { target - consumed }
    private var isOver: Bool { remaining < 0 }

    var body: some View {
        ZStack {
            // Raised container disc
            Circle()
                .fill(Color.surfaceRaised)
                .raisedSurface(cornerRadius: 999)

            // Recessed track
            Circle()
                .stroke(Color.surfaceFlat, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .padding(inset)

            // Progress arc — spring fill with gentle overshoot
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentFill, Color.accentFillPressed, Color.accentFill],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(inset)

            // End-cap bead — rides the tip of the arc
            if animatedProgress > 0.012 {
                Circle()
                    .fill(Color.accentFillPressed)
                    .frame(width: stroke - 6, height: stroke - 6)
                    .overlay(
                        Circle()
                            .fill(Color.onAccent.opacity(0.55))
                            .frame(width: 5, height: 5)
                    )
                    .offset(y: -pathRadius)
                    .rotationEffect(.degrees(animatedProgress * 360))
            }

            // Center readout — only remaining kcal, no inner pill
            VStack(spacing: 3) {
                Text(isOver ? "+\(Int(abs(remaining).rounded()))" : "\(Int(remaining.rounded()))")
                    .font(.sofraDisplayLarge)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.none, value: remaining) // no incrementing counter

                Text(isOver ? "kcal hedef üstü" : "kcal kalan")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .onAppear {
            withAnimation(.sofraSpring) { animatedProgress = progress }
        }
        .onChange(of: consumed) { _, _ in
            withAnimation(.sofraSpring) { animatedProgress = progress }
        }
    }
}
