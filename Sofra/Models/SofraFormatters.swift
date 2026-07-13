//
//  SofraFormatters.swift
//  Sofra — shared, cached display formatters.
//

import Foundation

enum SofraFormatters {
    static let turkishFullDay: DateFormatter = makeDateFormatter("d MMMM EEEE")
    static let turkishShortWeekday: DateFormatter = makeDateFormatter("EEE")
    static let time: DateFormatter = makeDateFormatter("HH:mm")

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = format
        return formatter
    }
}
