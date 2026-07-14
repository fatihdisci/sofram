//
//  Color+Widget.swift
//  CalorisorWidgetExtension — minimal color tokens for widget rendering.
//
//  Uses Color(name) without bundle parameter because Calorisor/Assets.xcassets
//  is shared with the widget target via project.yml source paths.
//

import SwiftUI

extension Color {
    static let bgPage        = Color("bgPage")
    static let surfaceRaised = Color("surfaceRaised")
    static let surfaceFlat   = Color("surfaceFlat")
    static let accentFill    = Color("accentFill")
    static let accentText    = Color("accentText")
    static let textPrimary   = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textMuted     = Color("textMuted")

    // Macro hues (graphics only — same warm-toned assets DailyView uses).
    static let macroProtein = Color("macroProtein")
    static let macroCarb    = Color("macroCarb")
    static let macroFat     = Color("macroFat")
}
