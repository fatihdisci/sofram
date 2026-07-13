//
//  SofraLottieView.swift
//  Sofra — Lottie wrapper for brand animations (empty states, paywall hero,
//  onboarding intro, rare celebration moments).
//
//  Why a wrapper around LottieView?
//  - Loads `LottieAnimation.named("…")` from the main bundle. If the asset is
//    missing, the lookup returns nil and the SwiftUI placeholder renders —
//    so the app stays shippable even before the brand Lottie files are
//    dropped in. The fallback is the caller's responsibility; pass an
//    `Image` or `SofraIconView` as `fallback` so the screen still reads
//    correctly pre-asset.
//  - Defaults to `.looping()` because every Sofra Lottie use case (empty
//    state, breathing hero, paywall bg) wants a continuous, quiet idle —
//    not a one-shot burst. Call sites that want a one-shot use LottieView
//    directly.
//  - Pins rendering to `.resizable().aspectRatio(contentMode: .fit)` so the
//    animation never overflows its caller's frame, even if the source
//    Lottie canvas is wider than the slot.
//
//  Asset pipeline (for the developer):
//  - Drop the .json (Bodymovin export from After Effects) into
//    `Sofra/Resources/Animations/<name>.json` and add it to the Sofra
//    target's "Copy Bundle Resources". xcodegen picks up anything under
//    `Sofra/Resources/` automatically, no extra config needed.
//  - Pass the bare name to the initializer (no extension).
//  - Test the empty-state fallback by temporarily renaming the asset —
//    the screen should still render with the static `fallback` View.
//

import SwiftUI
import Lottie

struct SofraLottieView<Fallback: View>: View {
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
