//
//  NavigationModel.swift
//  Sofra — app-wide flow state machine.
//
//  Camera is the root screen (no tab bar). Navigation flows:
//   camera → capture → analysis → result → daily
//   camera → textLog → result → daily
//   daily → camera (back)
//   daily → 7-day-summary (sheet)
//

import SwiftUI
import Observation
import UIKit

enum AppScreen: Equatable {
    case camera
    case analyzing(imageData: Data, uiImage: UIImage)
    case result(uiImage: UIImage, items: [VisionItem], source: ScanSource)
    case daily
    case textLog

    // Equatable: associated values compared by data/image identity
    static func == (lhs: AppScreen, rhs: AppScreen) -> Bool {
        switch (lhs, rhs) {
        case (.camera, .camera): return true
        case (.daily, .daily): return true
        case (.textLog, .textLog): return true
        case (.analyzing(let ld, let lu), .analyzing(let rd, let ru)):
            return ld == rd && lu === ru
        case (.result(let li, let lv, let ls), .result(let ri, let rv, let rs)):
            return li === ri && lv.map(\.name) == rv.map(\.name) && ls == rs
        default: return false
        }
    }
}

@MainActor
@Observable
final class NavigationModel {
    var screen: AppScreen = .camera

    /// Today's total calories (derived from saved ScanEntries for today).
    var todayCalories: Double = 0
    var todayProtein: Double = 0
    var todayCarbs: Double = 0
    var todayFat: Double = 0

    /// Quick counter values for today (persisted to DailyQuickCounter).
    var todayBreadSlices: Int = 0
    var todayTeaGlasses: Int = 0

    /// Whether to show the 7-day summary sheet from daily view.
    var showSevenDaySummary: Bool = false

    /// Whether to show the free-scan-limit screen.
    var showFreeScanLimit: Bool = false

    // MARK: - Navigation methods

    func goToCamera() {
        screen = .camera
    }

    func startAnalysis(imageData: Data, uiImage: UIImage) {
        screen = .analyzing(imageData: imageData, uiImage: uiImage)
    }

    func showResult(uiImage: UIImage, items: [VisionItem], source: ScanSource = .photo) {
        screen = .result(uiImage: uiImage, items: items, source: source)
    }

    func goToDaily() {
        screen = .daily
    }

    func goToTextLog() {
        screen = .textLog
    }
}
