//
//  Motion+Patterns.swift
//  Calorisor — iOS 17 native motion patterns ported from
//  amosgyamfi/open-swiftui-animations (the "Amo95" gist collection on
//  GitHub — pure inspiration, not a package dependency).
//
//  Every pattern in this file is built on iOS 17 APIs (`PhaseAnimator`,
//  `Animation.bouncy(duration:extraBounce:)`) so Sofra can stay dep-free for
//  everything except the cases that genuinely need a third-party library
//  (Pow for particle effects, Lottie for vector animation playback).
//
//  Pattern → Sofra use case map:
//  -------------------------------------------------------------------------
//  .sofraBouncy       → QuickCounterView "+1"/"-1" ghost rise (WIRED)
//                       Replaces `easeOut(0.4)` with a bouncy spring
//                       matching the spec's "Instagram like-count artışı
//                       hissi, ama abartısız" line.
//  .sofraSubtlePulse  → generic "breathing" / "ready" easer, available
//  CalorisorPulseShine    → PhaseAnimator wrapper for any future "primary
//                       action ready" indicator. NOT wired in MVP —
//                       camera button deliberately stays instant per the
//                       spec ("kamera açılınca hiçbir yükleme durumu
//                       görünmemeli"). Use this for: tencere kalibrasyonu
//                       "öğrenildi" tag, achievement unlocked, streak
//                       milestone badge.
//  CalorisorStaggerReveal → generic Phase Animator list reveal. NOT wired in
//                       MVP — AnalysisOverlay already implements stagger
//                       inline with a `for i in 1...n` loop, which is
//                       fine for the current 1-5 item range. Migrate here
//                       if the reveal list ever grows past ~10 items
//                       (Sofra Modu v1.1+).
//  -------------------------------------------------------------------------
//

import SwiftUI

// MARK: - Animation tokens

extension Animation {
    /// Sofra-tuned bouncy spring: iOS 17 `bouncy(duration:extraBounce:)`
    /// with `extraBounce: 0.15` — a hair of overshoot at the end, just
    /// enough to feel alive without becoming "abartılı" (the spec's
    /// anti-pattern for daily-use calorie tracking).
    ///
    /// Origin: amosgyamfi/open-swiftui-animations gists — bouncy
    /// family, `.bouncy(duration: 2, extraBounce: 0.5)` shape, retuned
    /// for Sofra's 0.5s window.
    ///
    /// Wired: `QuickCounterView.GhostLabel.onAppear`.
    static let sofraBouncy = Animation.bouncy(duration: 0.5, extraBounce: 0.15)

    /// Generic "breathing" / "ready" easer. Symmetric ease-in-out, 1.8s
    /// loop period. Use with `PhaseAnimator` for subtle continuous
    /// emphasis (NOT for the camera button — that one is intentionally
    /// instant).
    ///
    /// Origin: amosgyamfi's hue-rotation / WWDC24 invite example, where
    /// a PhaseAnimator drives a 1.6-2.0s easeInOut cycle.
    static let sofraSubtlePulse = Animation.easeInOut(duration: 1.8)
}

// MARK: - PhaseAnimator wrapper view (available, not wired)

/// Wraps content in a subtle breathing pulse via `PhaseAnimator`.
///
/// Use this for low-emphasis "this is alive" indicators — e.g. an
/// "öğrenildi" pin tag that breathes once after a tencere calibration
/// is saved (per the spec: "spring overshoot burada bilinçli olarak
/// biraz daha belirgin, çünkü bu nadir/özel bir aksiyon").
///
/// **Do NOT** use this on the camera button or any primary daily
/// action — those should feel instant and responsive, not
/// self-promoting.
struct SofraPulseShine<Content: View>: View {
    let scaleRange: ClosedRange<CGFloat>
    let opacityRange: ClosedRange<Double>
    @ViewBuilder let content: () -> Content

    init(
        scaleRange: ClosedRange<CGFloat> = 1.0...1.04,
        opacityRange: ClosedRange<Double> = 0.85...1.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.scaleRange = scaleRange
        self.opacityRange = opacityRange
        self.content = content
    }

    var body: some View {
        PhaseAnimator([false, true]) { phase in
            content()
                .scaleEffect(phase ? scaleRange.upperBound : scaleRange.lowerBound)
                .opacity(phase ? opacityRange.upperBound : opacityRange.lowerBound)
        } animation: { _ in
            .sofraSubtlePulse.repeatForever(autoreverses: true)
        }
    }
}

// MARK: - Stagger reveal container (available, not wired)

/// Reveals its children one by one with a configurable per-item delay.
/// Port of amosgyamfi's "Phase Animator with Springs" list reveal
/// pattern, simplified for iOS 17 SwiftUI's native `transition` API.
///
/// Use when you have a *growing* list of items to reveal (analysis
/// results, Sofra Modu v1.1 multi-item scans). For a fixed-size 1-5
/// item reveal, the inline `for i in 1...n` loop in `AnalysisOverlay`
/// is more readable.
///
/// Example:
/// ```swift
/// SofraStaggerReveal(items: items, perItem: 0.15) { item in
///     RecognizedItemBadge(item: item, index: 0)
/// }
/// ```
struct SofraStaggerReveal<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let perItem: Double
    @ViewBuilder let content: (Item) -> Content

    @State private var revealedCount: Int = 0

    var body: some View {
        VStack(spacing: Layout.Spacing.md) {
            ForEach(Array(items.prefix(revealedCount).enumerated()), id: \.element.id) { _, item in
                content(item)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .task {
            for i in 1...items.count {
                try? await Task.sleep(nanoseconds: UInt64(perItem * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    revealedCount = i
                }
            }
        }
    }
}
