//
//  LogMealIntent.swift
//  Calorisor — Siri / App Shortcuts entry for adding a meal (SF-EX05).
//
//  "Hey Siri, Calorisor'a yemek ekle" (or "Add a meal to Calorisor") captures a
//  spoken/typed meal description and hands it to the app. This is intentionally
//  a *draft-then-confirm* flow: the intent never analyzes or logs anything on
//  its own. It stashes the phrase, opens the app, and the app runs the SAME
//  text-analysis path used by the typed/voice log — landing the user on the
//  ResultView confirmation screen, where nothing is saved until they tap Kaydet.
//
//  Communication with the app is via UserDefaults (`IntentMealInbox`): the
//  intent writes the pending phrase, `CalorisorApp` reads and clears it the next
//  time the scene becomes active (openAppWhenRun guarantees that transition).
//

import AppIntents
import Foundation

// MARK: - Inbox bridge

/// Single-slot hand-off from the App-Intents context to the running app.
/// Standard `UserDefaults` is shared with the main app process, so no app group
/// is required for this in-app intent.
enum IntentMealInbox {
    private static let key = "calorisor.pendingIntentMeal"

    static func store(_ text: String) {
        UserDefaults.standard.set(text, forKey: key)
    }

    /// Returns the pending phrase (if any) and clears it, so a meal is only ever
    /// acted on once.
    static func consume() -> String? {
        let value = UserDefaults.standard.string(forKey: key)
        if value != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

// MARK: - Errors

enum LogMealIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyDescription

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyDescription:
            return "Ne yediğini anlayamadım, tekrar dener misin?"
        }
    }
}

// MARK: - Intent

struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Yemek Ekle"
    static var description = IntentDescription(
        "Ne yediğini söyle; Calorisor kalori ve makro tahmini için hazırlasın, sen onayla."
    )

    /// Bring the app forward so the user reviews and confirms on the result
    /// screen — we deliberately never log silently in the background.
    static var openAppWhenRun = true

    @Parameter(
        title: "Öğün",
        description: "Ne yediğin — örn. 2 kepçe mercimek çorbası, 1 dilim ekmek",
        requestValueDialog: "Ne yedin?"
    )
    var meal: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = meal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LogMealIntentError.emptyDescription
        }
        // The app-side analysis (network, free-scan gating) and confirmation
        // happen after launch — the intent only records the request.
        IntentMealInbox.store(trimmed)
        return .result()
    }
}

// MARK: - App Shortcuts

/// Turkish + English spoken phrases. `\(.applicationName)` resolves to the app
/// name so users say a natural command through Siri / the Shortcuts app.
struct CalorisorAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "\(.applicationName)'a yemek ekle",
                "\(.applicationName)'a öğün ekle",
                "\(.applicationName) ile yemek kaydet",
                "Add a meal to \(.applicationName)",
                "Log a meal in \(.applicationName)",
            ],
            shortTitle: "Yemek Ekle",
            systemImageName: "fork.knife"
        )
    }
}
