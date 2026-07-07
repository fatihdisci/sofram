//
//  CalorieRingView.swift
//  Sofra — central daily calorie ring with animated arc.
//
//  Per mikro-etkilesimler.md: single smooth arc animation (ease-out, 500ms)
//  to the new value — never an incrementing counter, never a hard jump.
//  Number displayed in the Geist Mono numeric-display token.
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

    private var remaining: Double {
        max(target - consumed, 0)
    }

    var body: some View {
        ZStack {
            // Background ring container
            Circle()
                .fill(Color.surfaceRaised)
                .raisedSurface(cornerRadius: 999)

            // Track ring
            Circle()
                .trim(from: 0, to: 1)
                .stroke(
                    Color.surfaceFlat,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .padding(20)

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
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(20)

            // Center numeric display
            VStack(spacing: 0) {
                Text("\(Int(remaining))")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.textPrimary)
                    .animation(.none, value: remaining) // no incrementing counter

                Text("kalan")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: 220, height: 220)
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
