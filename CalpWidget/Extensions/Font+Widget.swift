//
//  Font+Widget.swift
//  CalpWidgetExtension — minimal font aliases for widget rendering.
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
    static let calpDisplayNumeric = Font.system(size: 36, weight: .medium, design: .monospaced)
    static let calpNumericSmall   = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let calpCaption        = Font.system(size: 13, weight: .regular)
    static let calpLabel          = Font.system(size: 14, weight: .medium)
    static let calpBody           = Font.system(size: 16, weight: .regular)
}
