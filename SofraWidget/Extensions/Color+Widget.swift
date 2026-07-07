//
//  Color+Widget.swift
//  SofraWidgetExtension — minimal color tokens for widget rendering.
//
//  Uses Color(name) without bundle parameter because Sofra/Assets.xcassets
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
}
