//
//  ScanEntry.swift
//  Sofra — one AI scan (photo or text), local + CloudKit-synced.
//
//  CloudKit + SwiftData rules honored across every @Model in this app:
//   • every stored property has a default value or is optional,
//   • relationships are optional,
//   • no `@Attribute(.unique)` (CloudKit does not support unique constraints).
//

import Foundation
import SwiftData

enum ScanSource: String, Codable, CaseIterable {
    case photo
    case text
}

@Model
final class ScanEntry {
    /// Stable id (also used as the image-hash-independent local key). Not unique-
    /// constrained — CloudKit forbids that — uniqueness is guaranteed at creation.
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var source: ScanSource = ScanSource.photo

    /// The raw model JSON as returned by the proxy, kept for debugging / reprocessing.
    var rawAIResponse: String = ""

    /// Recognized items. Optional to satisfy CloudKit; treat nil as empty.
    @Relationship(deleteRule: .cascade, inverse: \LoggedItem.scanEntry)
    var items: [LoggedItem]? = []

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: ScanSource = .photo,
        rawAIResponse: String = "",
        items: [LoggedItem] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.rawAIResponse = rawAIResponse
        self.items = items
    }
}

extension ScanEntry {
    /// Non-optional convenience accessor for the items relationship.
    var itemsOrEmpty: [LoggedItem] { items ?? [] }
}
