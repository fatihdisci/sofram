//
//  CategorySlugMap.swift
//  Calp — Turkish display name for the JSON `category` slug.
//
//  The DB uses machine-friendly slugs ("corba", "kahvalti", "sut-urunu",
//  "ekmek") so they sort/filter nicely in code. The UI wants the
//  Turkish title-case form ("Çorba", "Kahvaltılık", "Süt Ürünü", "Ekmek").
//  This extension is the single place that maps one to the other — when
//  the DB grows beyond the current 4 categories, only this switch needs
//  to be touched (not every call site).
//

import Foundation

extension FoodReference {

    /// Turkish display name for the JSON `category` slug. Unknown slugs
    /// fall back to a title-cased form of the raw slug so the UI never
    /// shows a raw machine name.
    var categoryDisplayName: String {
        switch category {
        case "corba":     return "Çorba"
        case "kahvalti":  return "Kahvaltılık"
        case "sut-urunu": return "Süt Ürünü"
        case "ekmek":     return "Ekmek"
        default:          return category.capitalized
        }
    }
}