//
//  SofraApp.swift
//  Sofra
//

import SwiftUI
import SwiftData

@main
struct SofraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SofraModelContainer.shared)
    }
}
