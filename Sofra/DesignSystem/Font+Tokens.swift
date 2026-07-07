//
//  Font+Tokens.swift
//  Sofra — typography scale from design-tokens.json (typography.scale)
//
//  Geist Sans (UI) + Geist Mono (all numeric displays, tabular figures).
//
//  Geist static OTFs live in Sofra/Resources/Fonts/ and are registered in
//  Info.plist under `UIAppFonts`. If a font file ever goes missing, `.custom`
//  falls back to the system font at the same size (SF Pro / SF Mono).
//

import SwiftUI

extension Font {
    /// mono · 36 · medium — günlük halka merkez değeri (daily ring center number)
    static let sofraDisplayNumeric = SofraTypography.mono(size: 36, weight: .medium)
    /// sans · 28 · semibold — onboarding/paywall başlıkları
    static let sofraTitle          = SofraTypography.sans(size: 28, weight: .semibold)
    /// sans · 20 · medium — ekran başlıkları
    static let sofraHeading        = SofraTypography.sans(size: 20, weight: .medium)
    /// sans · 16 · regular — gövde metni
    static let sofraBody           = SofraTypography.sans(size: 16, weight: .regular)
    /// sans · 14 · medium — buton/etiket
    static let sofraLabel          = SofraTypography.sans(size: 14, weight: .medium)
    /// sans · 13 · regular — ikincil metin, zaman damgası
    static let sofraCaption        = SofraTypography.sans(size: 13, weight: .regular)
    /// mono · 14 · medium · tabular — makro gram değerleri, kart içi kalori sayıları
    static let sofraNumericSmall   = SofraTypography.mono(size: 14, weight: .medium)
}

enum SofraTypography {

    /// Geist font files are bundled in Sofra/Resources/Fonts/ and registered via
    /// Info.plist `UIAppFonts` (see the README there).
    static let geistAvailable = true

    static func sans(size: CGFloat, weight: Font.Weight) -> Font {
        if geistAvailable { return .custom(geistSansName(weight), size: size) }
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        if geistAvailable { return .custom(geistMonoName(weight), size: size) }
        // `.monospaced` design gives tabular figures on the system font too.
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // PostScript names Geist ships with — used only once `geistAvailable` is true.
    private static func geistSansName(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold: return "Geist-SemiBold"
        case .medium:          return "Geist-Medium"
        default:               return "Geist-Regular"
        }
    }

    private static func geistMonoName(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium, .semibold, .bold: return "GeistMono-Medium"
        default:                        return "GeistMono-Regular"
        }
    }
}
