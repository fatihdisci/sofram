//
//  String+TurkishNormalize.swift
//  Calorisor — Turkish diacritic fold + small synonym table for reference matching.
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
                .replacingOccurrences(of: "\u{0307}", with: "")     // combining dot from capital İ
                .replacingOccurrences(of: "\u{0131}", with: "i")   // ı
                .replacingOccurrences(of: "\u{011f}", with: "g")   // ğ
                .replacingOccurrences(of: "\u{00fc}", with: "u")   // ü
                .replacingOccurrences(of: "\u{015f}", with: "s")   // ş
                .replacingOccurrences(of: "\u{00f6}", with: "o")   // ö
                .replacingOccurrences(of: "\u{00e7}", with: "c")   // ç
        }

        /// Canonical key used for food-reference matching.
        /// Keeps the fold deterministic, treats parentheses as word separators,
        /// and collapses accidental extra spaces.
        static func foodKey(_ s: String) -> String {
            normalize(s)
                .replacingOccurrences(of: "(", with: " ")
                .replacingOccurrences(of: ")", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
        }

        // MARK: Synonym table

        /// Manual synonym pairs (both sides already Turkish-normalized).
        ///
        /// Each pair is bidirectional — `aliases(for:)` returns the OTHER side.
        static let synonymPairs: [(from: String, to: String)] = [
            ("beyaz ekmek",                "ekmek"),
            ("1 dilim ekmek",              "beyaz ekmek"),
            ("kirmizi mercimek corbasi",   "mercimek corbasi"),
            ("kasar",                      "kasar peyniri"),
            ("yogurt corbasi",             "yayla corbasi"),
            ("feta peyniri",               "beyaz peynir"),
            ("cay",                        "siyah cay sekersiz"),
            ("siyah cay",                  "siyah cay sekersiz"),
            ("pilav",                      "pirinc pilavi"),
            ("zeytin",                     "zeytin yesil"),
            ("zeytin",                     "zeytin siyah"),
            ("ton baligi",                 "ton baligi konserve"),
            ("kuru fasulye",               "kuru fasulye etli"),
            ("taze fasulye",               "taze fasulye zeytinyagli"),
            ("yaprak sarmasi",             "yaprak sarmasi etli"),
            ("biber dolmasi",              "biber dolmasi etli"),
            ("nohut yemegi",               "nohut yemegi etli"),
            ("turlu",                      "turlu sebze yemegi"),
            ("pirinc pilavi",              "pirinc pilavi sehriyeli"),
            ("bulgur pilavi",              "bulgur pilavi sebzeli"),
            ("eriste",                     "eriste tereyagli"),
            ("soslu makarna",              "soslu makarna bolonez"),
            ("makarna",                    "makarna peynirli"),
            ("domates",                    "domates cig"),
            ("salatalik",                  "salatalik cig"),
            ("havuc",                      "havuc cig"),
            ("havuc",                      "havuc haslanmis"),
            ("ispanak",                    "ispanak cig"),
            ("ispanak",                    "ispanak pismis"),
            ("kabak",                      "kabak cig"),
            ("kabak",                      "kabak haslanmis"),
            ("patlican",                   "patlican cig"),
            ("patlican",                   "patlican kozlenmis"),
            ("marul",                      "marul cig"),
            ("taze sogan",                 "taze sogan cig"),
            ("brokoli",                    "brokoli haslanmis"),
            ("karnabahar",                 "karnabahar haslanmis"),
            ("findik",                     "findik kavrulmus"),
            ("fistik",                     "fistik tuzlu"),
            ("antep fistigi",              "antep fistigi kavrulmus"),
            ("ay cekirdegi",               "ay cekirdegi tuzlu"),
            ("baklava",                    "baklava fistikli"),
            ("sutlac",                     "sutlac firin"),
            ("siyah cay",                  "siyah cay tek sekerli"),
            ("turk kahvesi",               "turk kahvesi sekersiz"),
            ("portakal suyu",              "portakal suyu taze"),
            ("nescafe",                    "nescafe 3'u 1 arada"),
            ("filtre kahve",               "filtre kahve sade"),
            ("kokorec",                    "kokorec yarim ekmek"),
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
