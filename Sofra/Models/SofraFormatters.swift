//
//  SofraFormatters.swift
//  Sofra — shared, cached display formatters.
//

import Foundation

enum SofraFormatters {
    /// Display formatters follow the active system locale. Export dates remain
    /// deliberately machine-readable in `DataExporter` and are not routed here.
    static let turkishFullDay: DateFormatter = makeDateFormatter("d MMMM EEEE")
    static let turkishShortWeekday: DateFormatter = makeDateFormatter("EEE")
    static let time: DateFormatter = makeDateFormatter("HH:mm")

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}
