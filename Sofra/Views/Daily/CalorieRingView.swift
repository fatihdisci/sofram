//
//  CalorieRingView.swift
//  Sofra — central daily calorie ring with animated arc.
//
//  Per mikro-etkilesimler.md: single smooth arc animation (ease-out, 500ms)
//  to the new value — never an incrementing counter, never a hard jump.
//  Number displayed in the Geist Mono numeric-display token.
//
//  Over-target is shown as neutral data ("+126 hedef üstü"), never as a
//  red/shaming state — consistent with the quick-counter philosophy.
//

import SwiftUI

struct CalorieRingView: View {
    let consumed: Double    // calories consumed so far
    let target: Double      // daily target (default if no profile)

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.0)
    }

    private var remaining: Double { target - consumed }

    var body: some View {
        ZStack {
            // Background ring container
            Circle()
                .fill(Color.surfaceRaised)
                .raisedSurface(cornerRadius: 999)

            // Track ring — inset look
            Circle()
                .stroke(
                    Color.surfaceFlat,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .padding(24)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [Color.accentFill, Color.accentFillPressed],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(24)

            // Center numeric display
            VStack(spacing: 2) {
                Text("\(Int(abs(remaining).rounded()))")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.none, value: remaining) // no incrementing counter

                Text(remaining >= 0 ? "kcal kalan" : "kcal hedef üstü")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)

                Text("\(Int(consumed)) / \(Int(target))")
                    .font(.sofraNumericSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Layout.Spacing.sm)
            }
        }
        .frame(width: 250, height: 250)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = progress
            }
        }
        .onChange(of: consumed) { _, _ in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = progress
            }
        }
    }
}
