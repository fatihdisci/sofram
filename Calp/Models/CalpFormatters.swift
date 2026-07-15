//
//  CalpFormatters.swift
//  Calp — shared, cached display formatters.
//

import Foundation

enum CalpFormatters {
    /// Display formatters follow the active system locale. Export dates remain
    /// deliberately machine-readable in `DataExporter` and are not routed here.
    static let turkishFullDay: DateFormatter = makeDateFormatter(template: "d MMMM EEEE")
    static let turkishShortWeekday: DateFormatter = makeDateFormatter(template: "EEE")
    static let time: DateFormatter = makeDateFormatter(template: "HH:mm")

    private static func makeDateFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
