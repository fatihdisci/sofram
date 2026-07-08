//
//  Surfaces.swift
//  Sofra — neomorphic raised / pressed surfaces (shadow_recipe in design-tokens.json)
//
//  This is NOT a single soft box-shadow. It is the two-tone border technique:
//  two literal shadows per surface (a light highlight offset one way, a darker
//  shadow offset the other). Values below are copied verbatim from shadow_recipe,
//  including the per-mode opacities. The colors themselves (borderHighlight /
//  borderShadow) are light/dark-aware asset colors, so only the opacities switch here.
//
//  Raised  → two `.drop` shadows (outer).
//  Pressed → two `.inner` shadows (inset) — the recipe marks these `inset: true`,
//            which SwiftUI expresses via the ShapeStyle `.inner` shadow, not the
//            `.shadow()` view modifier (that one cannot do insets).
//

import SwiftUI

struct RaisedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // shadow_recipe.<mode>.raised — larger radius/offset than v1 so cards read
        // as genuinely lifted against the low-contrast bej page.
        let highlightOpacity = scheme == .dark ? 0.85 : 1.0
        let shadowOpacity    = scheme == .dark ? 0.9 : 0.7
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Color.surfaceRaised
                            .shadow(.drop(color: .borderHighlight.opacity(highlightOpacity),
                                          radius: 7, x: -5, y: -5))
                            .shadow(.drop(color: .borderShadow.opacity(shadowOpacity),
                                          radius: 8, x: 5, y: 6))
                    )
            )
    }
}

struct PressedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // shadow_recipe.<mode>.pressed (inset) — sits on the recessed flat tone
        let shadowOpacity    = scheme == .dark ? 0.8 : 0.6
        let highlightOpacity = scheme == .dark ? 0.3 : 0.5
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Color.surfaceFlat
                            .shadow(.inner(color: .borderShadow.opacity(shadowOpacity),
                                           radius: 5, x: -3, y: -3))
                            .shadow(.inner(color: .borderHighlight.opacity(highlightOpacity),
                                           radius: 5, x: 3, y: 3))
                    )
            )
    }
}

extension View {
    /// Neomorphic raised surface (highlight top-left, shadow bottom-right).
    /// Default radius = raised-container (24) per the design tokens.
    func raisedSurface(cornerRadius: CGFloat = Layout.Radius.raisedContainer) -> some View {
        modifier(RaisedSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Neomorphic pressed / inset surface. Default radius = control (12).
    func pressedSurface(cornerRadius: CGFloat = Layout.Radius.control) -> some View {
        modifier(PressedSurfaceModifier(cornerRadius: cornerRadius))
    }
}
