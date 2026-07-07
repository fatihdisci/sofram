//
//  SofraApp.swift
//  Sofra
//

import SwiftUI
import SwiftData
import WidgetKit

@main
struct SofraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = NavigationModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigation)
        }
        .modelContainer(SofraModelContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Catch-up widget update for CloudKit sync or midnight rollover
                let context = SofraModelContainer.shared.mainContext
                let target = UserDefaults.standard.object(forKey: "sofra.dailyCalorieTarget") as? Double ?? 2000
                WidgetDataStore.saveCurrentDaySummary(
                    modelContext: context,
                    calorieTarget: target
                )
            }
        }
    }
}
