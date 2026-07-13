//
//  Font+Widget.swift
//  CalorisorWidgetExtension — minimal font aliases for widget rendering.
//
//  Uses system fonts (Geist is not bundled in either target yet).
//  Sizes and weights match the design tokens:
//    display-numeric: 36 medium mono
//    numeric-small:   14 medium mono (tabular)
//    caption:         13 regular
//    label:           14 medium
//    body:            16 regular
//

import SwiftUI

extension Font {
    static let sofraDisplayNumeric = Font.system(size: 36, weight: .medium, design: .monospaced)
    static let sofraNumericSmall   = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let sofraCaption        = Font.system(size: 13, weight: .regular)
    static let sofraLabel          = Font.system(size: 14, weight: .medium)
    static let sofraBody           = Font.system(size: 16, weight: .regular)
}
