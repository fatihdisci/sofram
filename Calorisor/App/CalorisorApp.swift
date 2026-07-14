//
//  CalorisorApp.swift
//  Calorisor
//

import SwiftUI
import SwiftData
import WidgetKit
import UserNotifications

@main
struct CalorisorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = NavigationModel()

    init() {
        // Route notification taps to the Bugün tab (SF-EX06.4 / EX07).
        UNUserNotificationCenter.current().delegate = MealReminderDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigation)
        }
        .modelContainer(CalorisorModelContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let context = CalorisorModelContainer.shared.mainContext

                // Repair any legacy quick-add rows stuck at 0 macros before
                // totals are recomputed below.
                QuickAddSeed.backfillMissingNutrition(context)

                // Catch-up widget update for CloudKit sync or midnight rollover
                let target = UserDefaults.standard.object(forKey: "calorisor.dailyCalorieTarget") as? Double ?? 2000
                WidgetDataStore.saveCurrentDaySummary(
                    modelContext: context,
                    calorieTarget: target
                )

                // A Siri / App-Intents meal request (SF-EX05) waiting to be
                // analyzed — route it into the text-log → result confirmation
                // flow now that the app is foreground.
                if let meal = IntentMealInbox.consume() {
                    navigation.presentIntentMeal(meal)
                }

                // A tapped notification (SF-EX06/07) asked to open the daily log.
                if UserDefaults.standard.bool(forKey: NotificationPrefs.openDailyKey) {
                    UserDefaults.standard.set(false, forKey: NotificationPrefs.openDailyKey)
                    navigation.goToDaily()
                }

                // Re-arm meal/no-log/summary notifications against today's state
                // (SF-EX06/07/08) — this is what makes "logged → reminder gone"
                // and "reset next day" work without background refresh.
                MealReminderService.shared.reschedule(modelContext: context)
            }
        }
    }
}
