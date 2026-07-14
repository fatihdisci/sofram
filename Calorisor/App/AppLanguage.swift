//
//  AppLanguage.swift
//  Calorisor — language preference (System / Türkçe / English).
//
//  Stores the user's language choice and applies it via AppleLanguages.
//  The change takes effect on the next app launch.
//

import SwiftUI

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case turkish = "tr"
    case english = "en"

    var displayName: String {
        switch self {
        case .system:  return String(localized: "Sistem")
        case .turkish: return String(localized: "Türkçe")
        case .english: return String(localized: "English")
        }
    }

    var identifier: String {
        rawValue
    }

    /// Locale suitable for formatting, AI prompts, and any runtime logic that
    /// needs the user's effective language before an app restart.
    var effectiveLocale: Locale {
        switch self {
        case .system:  return Locale.current
        case .turkish: return Locale(identifier: "tr_TR")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// Persisted preference key.
    static let storageKey = "calorisor.appLanguage"

    /// Current effective language — reads stored preference, falls back to system.
    static var current: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            apply(newValue)
        }
    }

    /// Write AppleLanguages so the bundle picks it up on next launch.
    private static func apply(_ lang: AppLanguage) {
        switch lang {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .turkish:
            UserDefaults.standard.set(["tr"], forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}
