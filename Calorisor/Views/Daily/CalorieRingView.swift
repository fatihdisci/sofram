//
//  CalorieRingView.swift
//  Calorisor — branded, open-C daily calorie gauge.
//
//  The gauge is intentionally not a generic completion ring. Its open track is
//  the Calorisor C; logged calorie groups leave quiet markers along the path,
//  the live cap moves when the total changes, and calories over target continue
//  through the mouth of the C as a neutral overflow tail.
//

import SwiftUI
import Pow

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
    /// Leaves a deliberate opening on the right, turning the track into a C.
    static let trackStart = 0.08
    static let trackEnd = 0.92
    static let trackSpan = trackEnd - trackStart

    static func overshootProgress(consumed: Double, target: Double) -> Double {
        guard target > 0, consumed > target else { return 0 }
        return min((consumed - target) / target, 1)
    }

    /// Converts each logged calorie group into a cumulative position on the C.
    /// The live cap owns the final position, so markers at the very end are
    /// omitted. Dense days are sampled evenly to keep the gauge legible.
    static func markerProgresses(
        segments: [Double],
        target: Double,
        maximumCount: Int = 7
    ) -> [Double] {
        guard target > 0, maximumCount > 0 else { return [] }

        var cumulative = 0.0
        let positions = segments.compactMap { calories -> Double? in
            guard calories > 0, calories.isFinite else { return nil }
            cumulative += calories
            let value = min(cumulative / target, 1)
            return value < 0.985 ? value : nil
        }

        guard positions.count > maximumCount else { return positions }
        guard maximumCount > 1 else { return [positions[positions.count / 2]] }

        return (0..<maximumCount).map { index in
            let fraction = Double(index) / Double(maximumCount - 1)
            let sourceIndex = Int((fraction * Double(positions.count - 1)).rounded())
            return positions[sourceIndex]
        }
    }
}

struct CalorieRingView: View {
    let consumed: Double
    let target: Double
    var calorieSegments: [Double] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0
    @State private var animatedOvershootProgress: Double = 0
    @State private var changeEffectID = UUID()
    @State private var capPulse = false
    @State private var hasAppeared = false
    @AppStorage("calorisor.ringDisplayMode") private var displayModeRaw = RingDisplayMode.remaining.rawValue

    private let gaugeSize: CGFloat = 244
    private let stroke: CGFloat = 18
    private let inset: CGFloat = 25
    private let maximumOverflowLength: CGFloat = 38

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    private var remaining: Double { target - consumed }
    private var isOver: Bool { remaining < 0 }
    private var overshootProgress: Double {
        CalorieRingMetrics.overshootProgress(consumed: consumed, target: target)
    }
    private var markerProgresses: [Double] {
        CalorieRingMetrics.markerProgresses(segments: calorieSegments, target: target)
    }
    private var displayMode: RingDisplayMode {
        RingDisplayMode(rawValue: displayModeRaw) ?? .remaining
    }

    private var displayValue: String {
        switch displayMode {
        case .remaining:
            return isOver ? "+\(Int(abs(remaining).rounded()))" : "\(Int(max(remaining, 0).rounded()))"
        case .consumed:
            return "\(Int(consumed.rounded()))"
        case .target:
            return "\(Int(target.rounded()))"
        }
    }

    private var displayLabel: String {
        switch displayMode {
        case .remaining:
            return isOver ? String(localized: "kcal hedef üstü") : String(localized: "kcal kalan")
        case .consumed:
            return String(localized: "kcal yenen")
        case .target:
            return String(localized: "kcal hedef")
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceRaised)
                .overlay(Circle().stroke(Color.borderHairline, lineWidth: 1))

            GeometryReader { proxy in
                let size = proxy.size
                let activePoint = activePoint(in: size)

                Circle()
                    .trim(from: CalorieRingMetrics.trackStart, to: CalorieRingMetrics.trackEnd)
                    .stroke(
                        Color.borderHairline,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .padding(inset)

                Circle()
                    .trim(
                        from: CalorieRingMetrics.trackStart,
                        to: CalorieRingMetrics.trackStart
                            + CalorieRingMetrics.trackSpan * animatedProgress
                    )
                    .stroke(
                        Color.accentFill,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .padding(inset)

                ForEach(Array(markerProgresses.enumerated()), id: \.offset) { _, marker in
                    let point = point(for: marker, in: size)
                    Circle()
                        .fill(Color.surfaceRaised)
                        .overlay(Circle().stroke(Color.accentFillPressed, lineWidth: 2))
                        .frame(width: 8, height: 8)
                        .position(point)
                        .scaleEffect(animatedProgress + 0.005 >= marker ? 1 : 0.25)
                        .opacity(animatedProgress + 0.005 >= marker ? 1 : 0)
                }

                if animatedOvershootProgress > 0 {
                    Path { path in
                        path.move(to: point(for: 1, in: size))
                        path.addLine(to: overflowPoint(in: size))
                    }
                    .stroke(
                        Color.accentFillPressed,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                }

                ZStack {
                    Circle()
                        .fill(Color.accentTintBg)
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(isOver ? Color.accentFillPressed : Color.accentFill)
                        .frame(width: 12, height: 12)
                }
                .position(activePoint)
                .scaleEffect(capPulse ? 1.16 : 1)
                .changeEffect(
                    .spray(origin: .center) {
                        Circle()
                            .fill(Color.accentFill)
                            .frame(width: 4, height: 4)
                    },
                    value: changeEffectID
                )
            }

            VStack(spacing: 5) {
                Text(displayValue)
                    .font(.calorisorDisplayLarge)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: 148)
                    .contentTransition(.numericText())

                Text(displayLabel)
                    .font(.calorisorCaption)
                    .foregroundStyle(Color.textMuted)
                    .contentTransition(.interpolate)

                modeIndicator
                    .padding(.top, 5)
            }
            .animation(reduceMotion ? nil : .calorisorSpring, value: displayModeRaw)
        }
        .frame(width: gaugeSize, height: gaugeSize)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .calorisorSpring) {
                displayModeRaw = displayMode.next.rawValue
            }
        }
        .sensoryFeedback(.selection, trigger: displayModeRaw)
        .particleLayer(name: "calorieGaugeTrail")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "Günlük kalori"))
        .accessibilityHint(String(localized: "Kalan, yenen ve hedef kalorileri arasında geçiş yapar"))
        .accessibilityValue("\(displayValue) \(displayLabel)")
        .onAppear {
            withAnimation(reduceMotion ? nil : .calorisorSpring) {
                animatedProgress = progress
                animatedOvershootProgress = overshootProgress
            }
            hasAppeared = true
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? nil : .calorisorSpring) {
                animatedProgress = newValue
            }
        }
        .onChange(of: overshootProgress) { _, newValue in
            withAnimation(reduceMotion ? nil : .calorisorSpring) {
                animatedOvershootProgress = newValue
            }
        }
        .onChange(of: consumed) { oldValue, newValue in
            guard hasAppeared, oldValue != newValue else { return }
            if !reduceMotion {
                if newValue > oldValue {
                    changeEffectID = UUID()
                }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                    capPulse = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 170_000_000)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        capPulse = false
                    }
                }
            }
        }
    }

    private var modeIndicator: some View {
        HStack(spacing: 5) {
            ForEach(RingDisplayMode.allCases, id: \.self) { mode in
                Capsule()
                    .fill(mode == displayMode ? Color.accentFill : Color.borderHairline)
                    .frame(width: mode == displayMode ? 14 : 5, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .calorisorSpring, value: displayModeRaw)
        .accessibilityHidden(true)
    }

    private func point(for progress: Double, in size: CGSize) -> CGPoint {
        let clamped = min(max(progress, 0), 1)
        let fraction = CalorieRingMetrics.trackStart + CalorieRingMetrics.trackSpan * clamped
        let angle = fraction * 2 * Double.pi
        let radius = (min(size.width, size.height) - 2 * inset) / 2
        return CGPoint(
            x: size.width / 2 + radius * CGFloat(cos(angle)),
            y: size.height / 2 + radius * CGFloat(sin(angle))
        )
    }

    private func overflowPoint(in size: CGSize) -> CGPoint {
        let endpoint = point(for: 1, in: size)
        let angle = CalorieRingMetrics.trackEnd * 2 * Double.pi
        let length = maximumOverflowLength * animatedOvershootProgress
        return CGPoint(
            x: endpoint.x - CGFloat(sin(angle)) * length,
            y: endpoint.y + CGFloat(cos(angle)) * length
        )
    }

    private func activePoint(in size: CGSize) -> CGPoint {
        animatedOvershootProgress > 0
            ? overflowPoint(in: size)
            : point(for: animatedProgress, in: size)
    }
}
