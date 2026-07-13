//
//  DataExporter.swift
//  Sofra — UTF-8 BOM CSV export for spreadsheet compatibility.
//

import Foundation

enum DataExporter {
    static let header = "tarih,saat,kaynak,öğe,birim,miktar,gram,kcal,protein,karb,yağ,kaynak_tipi"

    static func csvData(scans: [ScanEntry]) -> Data {
        var lines = [header]

        for scan in scans.sorted(by: { $0.timestamp < $1.timestamp }) {
            for item in scan.itemsOrEmpty {
                lines.append([
                    dateFormatter.string(from: scan.timestamp),
                    timeFormatter.string(from: scan.timestamp),
                    scan.source.rawValue,
                    item.name,
                    item.portionUnit.rawValue,
                    number(item.quantity),
                    number(item.estimatedGrams),
                    number(item.calories),
                    number(item.protein),
                    number(item.carbs),
                    number(item.fat),
                    item.valueSource ?? "",
                ].map(escape).joined(separator: ","))
            }
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    static func writeTemporaryCSV(scans: [ScanEntry], now: Date = .now) throws -> URL {
        let filename = "Sofra-Verileri-\(filenameDateFormatter.string(from: now)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csvData(scans: scans).write(to: url, options: .atomic)
        return url
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func number(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.never)
                .precision(.fractionLength(0...3))
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
