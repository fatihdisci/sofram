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

enum RingDisplayMode: String, CaseIterable {
    case remaining
    case consumed
    case target

    var next: RingDisplayMode {
        switch self {
        case .remaining: return .consumed
        case .consumed: return .target
        case .target: return .remaining
        }
    }
}

enum CalorieRingMetrics {
    static func overshootProgress(consumed: Double, target: Double) -> Double {
        guard target > 0, consumed > target else { return 0 }
        return min((consumed - target) / target, 1)
    }
}

struct CalorieRingView: View {
    let consumed: Double    // calories consumed so far
    let target: Double      // daily target (default if no profile)

    @State private var animatedProgress: Double = 0
    @State private var animatedOvershootProgress: Double = 0
    @AppStorage("sofra.ringDisplayMode") private var displayModeRaw = RingDisplayMode.remaining.rawValue

    private let ringSize: CGFloat = 220
    private let stroke: CGFloat = 18
    private let inset: CGFloat = 22

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.0)
    }

    private var remaining: Double { target - consumed }
    private var isOver: Bool { remaining < 0 }
    private var overshootProgress: Double {
        CalorieRingMetrics.overshootProgress(consumed: consumed, target: target)
    }
    private var displayMode: RingDisplayMode {
        RingDisplayMode(rawValue: displayModeRaw) ?? .remaining
    }

    private var displayValue: String {
        switch displayMode {
        case .remaining:
            return isOver ? "+\(Int(abs(remaining).rounded()))" : "\(Int(remaining.rounded()))"
        case .consumed:
            return "\(Int(consumed.rounded()))"
        case .target:
            return "\(Int(target.rounded()))"
        }
    }

    private var displayLabel: String {
        switch displayMode {
        case .remaining: return isOver ? "kcal hedef üstü" : "kcal kalan"
        case .consumed: return "kcal yenen"
        case .target: return "kcal hedef"
        }
    }

    var body: some View {
        ZStack {
            // Deliberately flat: one quiet track and one data-colour arc.
            Circle()
                .stroke(Color.borderHairline, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .padding(inset)

            // Progress is a single solid colour — no decorative gradient or bead.
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    Color.accentFill,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(inset)

            // A neutral inner second lap visualizes calories over target.
            if animatedOvershootProgress > 0 {
                Circle()
                    .trim(from: 0, to: animatedOvershootProgress)
                    .stroke(
                        Color.accentFillPressed,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(inset + 6)
            }

            // Center readout stays visually quiet so the number leads.
            VStack(spacing: 3) {
                Text(displayValue)
                    .font(.sofraDisplayLarge)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 148)
                    .contentTransition(.numericText())
                    .animation(.sofraSpring, value: displayModeRaw)

                Text(displayLabel)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
                    .contentTransition(.interpolate)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .contentShape(Circle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.sofraSpring) {
                displayModeRaw = displayMode.next.rawValue
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Kalan, yenen ve hedef kalorileri arasında geçiş yapar")
        .onAppear {
            withAnimation(.sofraSpring) {
                animatedProgress = progress
                animatedOvershootProgress = overshootProgress
            }
        }
        .onChange(of: progress) { _, _ in
            withAnimation(.sofraSpring) { animatedProgress = progress }
        }
        .onChange(of: overshootProgress) { _, _ in
            withAnimation(.sofraSpring) { animatedOvershootProgress = overshootProgress }
        }
    }
}
