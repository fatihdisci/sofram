//
//  SofraApp.swift
//  Sofra
//

import SwiftUI
import SwiftData

@main
struct SofraApp: App {
    @State private var navigation = NavigationModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigation)
        }
        .modelContainer(SofraModelContainer.shared)
    }
}
