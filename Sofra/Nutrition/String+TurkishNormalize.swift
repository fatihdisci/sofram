//
//  String+TurkishNormalize.swift
//  Sofra — Turkish diacritic fold + small synonym table for reference matching.
//
//  Pure-function helpers used by ReferenceReconciler and TurkishFoodReference
//  to fold "Mercimek Çorbası" / "mercimek corbasi" / "MERCİMEK ÇORBASI" into
//  a single canonical form so DB lookup is locale-independent and order-stable.
//
//  No Foundation locale awareness — we explicitly want the same fold regardless
//  of the device language (the food DB is Turkish-source).
//

import Foundation

extension String {

    enum Turkish {

        // MARK: Diacritic fold

        /// Lowercase + Turkish diacritic fold:
        ///   ı → i · ğ → g · ü → u · ş → s · ö → o · ç → c
        ///
        /// The replacement order is fixed (any diacritic that's also a Latin
        /// letter — e.g. `i` → would be a no-op — stays put). Whitespace is
        /// preserved; trimming happens at the call site if needed.
        static func normalize(_ s: String) -> String {
            guard !s.isEmpty else { return s }
            return s
                .lowercased()
                .replacingOccurrences(of: "\u{0131}", with: "i")   // ı
                .replacingOccurrences(of: "\u{011f}", with: "g")   // ğ
                .replacingOccurrences(of: "\u{00fc}", with: "u")   // ü
                .replacingOccurrences(of: "\u{015f}", with: "s")   // ş
                .replacingOccurrences(of: "\u{00f6}", with: "o")   // ö
                .replacingOccurrences(of: "\u{00e7}", with: "c")   // ç
        }

        // MARK: Synonym table

        /// Manual synonym pairs (both sides already Turkish-normalized).
        ///
        /// Phase v1 size: 5 pairs covering the most common AI mis-classifications
        /// observed against the 32-item DB. Expand when the DB grows beyond
        /// ~100 items or when the AI proxy starts emitting new dish variants.
        /// Each pair is bidirectional — `aliases(for:)` returns the OTHER side.
        static let synonymPairs: [(from: String, to: String)] = [
            ("beyaz ekmek",    "ekmek"),
            ("kasar peyniri",  "kasar"),
            ("yogurt corbasi", "yayla corbasi"),
            ("patates salata", "patates"),
            ("yesil mercimek","mercimek"),
        ]

        /// Returns the matching aliases for a normalized query, or empty array
        /// when the query has no synonym entry. Both the AI's `name` and each
        /// DB row's `name` should be run through `normalize` before this lookup.
        static func aliases(for normalized: String) -> [String] {
            guard !normalized.isEmpty else { return [] }
            return synonymPairs.compactMap { from, to in
                from == normalized ? to : (to == normalized ? from : nil)
            }
        }
    }
}