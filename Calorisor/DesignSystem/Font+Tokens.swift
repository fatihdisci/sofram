//
//  Font+Tokens.swift
//  Calorisor — typography scale from design-tokens.json (typography.scale)
//
//  Geist Sans (UI) + Geist Mono (all numeric displays, tabular figures).
//
//  Geist static OTFs live in Calorisor/Resources/Fonts/ and are registered in
//  Info.plist under `UIAppFonts`. If a font file ever goes missing, `.custom`
//  falls back to the system font at the same size (SF Pro / SF Mono).
//

import SwiftUI

extension Font {
    /// mono · 58 · medium — hero kalori sayısı (daily ring). Büyük, hafif, tabular.
    static let sofraDisplayLarge   = SofraTypography.mono(size: 58, weight: .medium)
    /// mono · 34 · medium — ikincil büyük sayılar (result totals, stat cell)
    static let sofraDisplayNumeric = SofraTypography.mono(size: 34, weight: .medium)
    /// sans · 30 · semibold — onboarding/paywall başlıkları
    static let sofraTitle          = SofraTypography.sans(size: 30, weight: .semibold)
    /// sans · 22 · semibold — ekran başlıkları / greeting
    static let sofraHeading        = SofraTypography.sans(size: 22, weight: .semibold)
    /// sans · 12 · semibold · uppercase-tracking — bölüm başlıkları (eyebrow)
    static let sofraEyebrow        = SofraTypography.sans(size: 12, weight: .semibold)
    /// sans · 16 · regular — gövde metni
    static let sofraBody           = SofraTypography.sans(size: 16, weight: .regular)
    /// sans · 14 · medium — buton/etiket
    static let sofraLabel          = SofraTypography.sans(size: 14, weight: .medium)
    /// sans · 13 · regular — ikincil metin, zaman damgası
    static let sofraCaption        = SofraTypography.sans(size: 13, weight: .regular)
    /// mono · 15 · medium · tabular — makro gram değerleri, kart içi kalori sayıları
    static let sofraNumericSmall   = SofraTypography.mono(size: 15, weight: .medium)
}

enum SofraTypography {

    /// Geist font files are bundled in Calorisor/Resources/Fonts/ and registered via
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
