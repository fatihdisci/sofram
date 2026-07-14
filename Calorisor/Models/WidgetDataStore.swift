//
//  WidgetDataStore.swift
//  Calorisor — read/write WidgetDailySummary to shared App Group UserDefaults.
//
//  The main app calls save(_:) after each data mutation. The widget calls load()
//  in its TimelineProvider. Both targets include this file; no conditional
//  compilation needed because save/load are pure Foundation and the only
//  side-effect (WidgetCenter.reloadAllTimelines) is handled separately
//  in WidgetDataStore+MainApp.swift (main app target only).
//
//  Included in both the Calorisor (main app) and CalorisorWidgetExtension targets.
//

import Foundation

enum WidgetDataStore {

    /// Must match the App Group ID in both entitlement files.
    static let appGroupID = "group.com.fatih.calorisor"

    /// Key under which the JSON blob is stored in shared UserDefaults.
    static let summaryKey = "calorisor.widget.dailySummary"
    static let pendingFrequentMealsKey = "calorisor.widget.pendingFrequentMeals"

    // MARK: - Shared UserDefaults

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Save (main app)

    /// Encodes the summary as JSON and writes it to shared UserDefaults.
    /// Called by the main app after every data mutation.
    static func save(_ summary: WidgetDailySummary) {
        guard let data = try? JSONEncoder().encode(summary) else {
            #if DEBUG
            print("⚠️ WidgetDataStore: failed to encode WidgetDailySummary")
            #endif
            return
        }
        guard let defaults else {
            #if DEBUG
            print("⚠️ WidgetDataStore: UserDefaults(suiteName:) returned nil — check App Group entitlement")
            #endif
            return
        }
        defaults.set(data, forKey: summaryKey)
    }

    // MARK: - Load (widget)

    /// Reads and decodes the summary from shared UserDefaults.
    /// Returns `.empty` if no data has been written yet (first launch),
    /// the data is malformed, or the App Group isn't configured.
    static func load() -> WidgetDailySummary {
        guard let defaults,
              let data = defaults.data(forKey: summaryKey),
              let summary = try? JSONDecoder().decode(WidgetDailySummary.self, from: data)
        else {
            return .empty
        }
        return summary
    }

    /// Queues a value snapshot for the main app to materialize as SwiftData.
    /// The widget cannot safely open the app's ModelContainer, so it writes a
    /// durable App Group command and updates its displayed totals immediately.
    static func enqueueFrequentMeal(_ meal: FrequentMealSnapshot) {
        guard let defaults else { return }
        var pending = (defaults.data(forKey: pendingFrequentMealsKey)
            .flatMap { try? JSONDecoder().decode([FrequentMealSnapshot].self, from: $0) }) ?? []
        pending.append(meal)
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingFrequentMealsKey)
        }

        var summary = load()
        summary.calories += meal.totalCalories
        summary.protein += meal.totalProtein
        summary.carbs += meal.totalCarbs
        summary.fat += meal.totalFat
        summary.lastUpdated = .now
        summary.progress = min(summary.calories / max(summary.target, 1), 1)
        summary.remaining = max(summary.target - summary.calories, 0)
        save(summary)
    }

    /// Main-app side of the widget/Siri command bridge.
    static func consumeFrequentMeals() -> [FrequentMealSnapshot] {
        guard let defaults,
              let data = defaults.data(forKey: pendingFrequentMealsKey),
              let meals = try? JSONDecoder().decode([FrequentMealSnapshot].self, from: data)
        else { return [] }
        defaults.removeObject(forKey: pendingFrequentMealsKey)
        return meals
    }
}
