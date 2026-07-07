//
//  Color+Tokens.swift
//  Sofra — Yumuşak Sofra (Soft Native) design system
//
//  Typed accessors for every color token in design-tokens.json.
//  Each accessor resolves to a Color Set in Assets.xcassets/Colors, which carries
//  the light + dark variant, so the whole app is automatically light/dark aware.
//
//  Usage rule from the design brief (do not violate):
//  - `accentFill` is for icon/graphic/button fills ONLY. It fails 4.5:1 as body text.
//  - For emphasized text/numbers (e.g. "86g protein") use `accentText`.
//  - Body text always comes from `textPrimary` / `textSecondary`.
//

import SwiftUI

extension Color {

    // MARK: Backgrounds & surfaces
    static let bgPage        = Color("bgPage", bundle: .main)
    static let surfaceRaised = Color("surfaceRaised", bundle: .main)
    static let surfaceFlat   = Color("surfaceFlat", bundle: .main)

    // MARK: Borders (neomorphism dual-tone technique — see shadow recipe / Surfaces.swift)
    static let borderHighlight = Color("borderHighlight", bundle: .main)
    static let borderShadow    = Color("borderShadow", bundle: .main)
    static let borderHairline  = Color("borderHairline", bundle: .main)

    // MARK: Text (high-contrast scale — never render text in accentFill)
    static let textPrimary   = Color("textPrimary", bundle: .main)
    static let textSecondary = Color("textSecondary", bundle: .main)
    static let textMuted     = Color("textMuted", bundle: .main)

    // MARK: Accent (copper)
    static let accentFill        = Color("accentFill", bundle: .main)        // fills/icons/graphics only
    static let accentFillPressed = Color("accentFillPressed", bundle: .main)
    static let accentText        = Color("accentText", bundle: .main)        // emphasized text/numbers
    static let onAccent          = Color("onAccent", bundle: .main)          // label on an accentFill surface
    static let accentTintBg      = Color("accentTintBg", bundle: .main)      // subtle tinted background
}

extension Color {
    /// Hex initializer (`#RGB`, `#RRGGBB`, `#RRGGBBAA`).
    ///
    /// Production colors come from the asset-catalog accessors above (which are
    /// light/dark aware). This initializer is kept for one-off/debug/preview use
    /// where a literal token value from design-tokens.json is needed directly.
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch raw.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255,
                            (value >> 8 & 0xF) * 17,
                            (value >> 4 & 0xF) * 17,
                            (value & 0xF) * 17)
        case 6: // RRGGBB (24-bit)
            (a, r, g, b) = (255, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        case 8: // RRGGBBAA (32-bit)
            (a, r, g, b) = (value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
