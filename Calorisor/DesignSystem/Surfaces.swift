//
//  Surfaces.swift
//  Calorisor — flat, bordered surfaces.
//
//  The method names remain for call-site compatibility while the old
//  neomorphic shadows are deliberately removed. Hierarchy comes from fill,
//  a one-point border, whitespace and type — never a faux physical elevation.
//

import SwiftUI

struct RaisedSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 1)
            )
    }
}

struct PressedSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surfaceFlat)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Flat primary surface. The legacy name keeps the existing view API stable.
    func raisedSurface(cornerRadius: CGFloat = Layout.Radius.raisedContainer) -> some View {
        modifier(RaisedSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Flat secondary surface. The legacy name keeps the existing view API stable.
    func pressedSurface(cornerRadius: CGFloat = Layout.Radius.control) -> some View {
        modifier(PressedSurfaceModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Sofra press button style

/// Shared press feel for all tappable card-buttons.
/// - scale 0.97 on press
/// - surface "sinks" via a subtle flat overlay
/// - light haptic on press-down
struct SofraPressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Layout.Radius.card

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .overlay(
                configuration.isPressed
                    ? RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.surfaceFlat.opacity(0.35))
                    : nil
            )
            .animation(.easeOut(duration: Layout.Motion.fast), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}
