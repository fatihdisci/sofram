//
//  PortionUnit.swift
//  Sofra — Turkish household portion vocabulary (core product concept).
//
//  The AI's raw gram output is always mapped to one of these units; users correct
//  results via steppers/pickers in these units, never raw grams.
//
//  This is a *superset* reconciling two source lists (see PHASE_1_NOTES.md):
//   • the Phase 1 model spec (…, gram-fallback)
//   • the vision schema household_unit enum (…, tencere, adet)
//  so a decoded scan item can always be represented, plus a `.gram` fallback for
//  anything unexpected.
//
//  Raw values match the JSON `household_unit` strings exactly, so decoding maps 1:1.
//

import Foundation

enum PortionUnit: String, Codable, CaseIterable, Identifiable, Hashable {
    case kepce        = "kepçe"          // ladle — soups, stews
    case yemekKasigi  = "yemek kaşığı"   // tbsp — sauces, small sides
    case suBardagi    = "su bardağı"     // glass — liquids, rice, grains
    case cayBardagi   = "çay bardağı"    // tea glass — tea, small liquids
    case dilim        = "dilim"          // slice — bread, cake, watermelon
    case avuc         = "avuç"           // handful — nuts, chips, snacks
    case kase         = "kase"           // bowl — salads, yogurt dishes
    case tencere      = "tencere"        // pot — shared-portion total (Sofra Modu, v1.1)
    case adet         = "adet"           // piece/count — egg, simit, meatball
    case gram         = "gram"           // raw-gram fallback

    var id: String { rawValue }

    /// User-facing label, localized to the app language.
    var displayName: String {
        String(localized: String.LocalizationValue(rawValue))
    }

    /// Maps an API `household_unit` string to a unit, falling back to `.gram`
    /// for any value outside the known set.
    init(apiValue: String) {
        self = PortionUnit(rawValue: apiValue) ?? .gram
    }

    /// Optional custom icon from the Sofra icon set (used by steppers/pickers).
    var icon: SofraIcon? {
        switch self {
        case .kepce:       return .kepce
        case .yemekKasigi: return .kasik
        case .cayBardagi:  return .cayBardagi
        case .dilim:       return .ekmekDilimi
        case .kase:        return .kase
        case .tencere:     return .tencere
        case .suBardagi, .avuc, .adet, .gram: return nil
        }
    }
}
