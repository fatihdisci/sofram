//
//  CalpLottieView.swift
//  Calp — Lottie wrapper for brand animations (empty states, paywall hero,
//  onboarding intro, rare celebration moments).
//
//  STATUS (see VISUAL_DIFFERENTIATION_NOTES.md §B): no brand-approved Lottie
//  asset ships yet, so this wrapper currently has NO consumer — it is retained
//  deliberately as the single, documented future integration point. The empty
//  states that would use it render purpose-built static SwiftUI vectors for now
//  (Reduce-Motion-safe, no dependence on a missing asset). Drop a brand asset
//  into Resources/Animations/ and re-wire one high-value screen to light it up;
//  do NOT add stock LottieFiles content that doesn't match Calp's language.
//
//  Why a wrapper around LottieView?
//  - Loads `LottieAnimation.named("…")` from the main bundle. If the asset is
//    missing, the lookup returns nil and the SwiftUI placeholder renders —
//    so the app stays shippable even before the brand Lottie files are
//    dropped in. The fallback is the caller's responsibility; pass an
//    `Image` or `CalpIconView` as `fallback` so the screen still reads
//    correctly pre-asset.
//  - Defaults to `.looping()` because every Calp Lottie use case (empty
//    state, breathing hero, paywall bg) wants a continuous, quiet idle —
//    not a one-shot burst. Call sites that want a one-shot use LottieView
//    directly.
//  - Pins rendering to `.resizable().aspectRatio(contentMode: .fit)` so the
//    animation never overflows its caller's frame, even if the source
//    Lottie canvas is wider than the slot.
//
//  Asset pipeline (for the developer):
//  - Drop the .json (Bodymovin export from After Effects) into
//    `Calp/Resources/Animations/<name>.json` and add it to the Calp
//    target's "Copy Bundle Resources". xcodegen picks up anything under
//    `Calp/Resources/` automatically, no extra config needed.
//  - Pass the bare name to the initializer (no extension).
//  - Test the empty-state fallback by temporarily renaming the asset —
//    the screen should still render with the static `fallback` View.
//

import SwiftUI
import Lottie

struct CalpLottieView<Fallback: View>: View {
    /// Bare asset name (no extension). Resolves to `<name>.json` in the main
    /// bundle via `LottieAnimation.named(_:)`. If missing → fallback shown.
    let name: String

    /// Render speed. 1.0 = Lottie's authored speed; 0.5 = half-speed idle
    /// (use this for "breathing" / paywall bg).
    let speed: CGFloat

    let contentMode: ContentMode

    @ViewBuilder let fallback: () -> Fallback

    init(
        _ name: String,
        speed: CGFloat = 1.0,
        contentMode: ContentMode = .fit,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.name = name
        self.speed = speed
        self.contentMode = contentMode
        self.fallback = fallback
    }

    var body: some View {
        LottieView {
            // Synchronous bundle lookup → `LottieAnimation?` (nil = no asset).
            // The SwiftUI LottieView's placeholder closure takes over when nil.
            LottieAnimation.named(name)
        } placeholder: {
            fallback()
        }
        .looping()
        .resizable()
        .aspectRatio(contentMode: contentMode)
        .accessibilityHidden(true)
    }
}
