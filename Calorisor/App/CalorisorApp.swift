//
//  CalorisorApp.swift
//  Calorisor
//

import SwiftUI
import SwiftData
import WidgetKit

@main
struct CalorisorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = NavigationModel()

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
            }
        }
    }
}
