//
//  DailyQuickCounter.swift
//  Sofra — the bread/tea quick-counter, one row per day.
//
//  `date` is normalized to the start of the day by the caller. No unique constraint
//  (CloudKit forbids it); the app fetches-or-creates the row for a given day.
//

import Foundation
import SwiftData

@Model
final class DailyQuickCounter {
    var date: Date = Date()          // start-of-day
    var breadSlices: Int = 0         // ekmek dilimi
    var teaGlasses: Int = 0          // çay bardağı

    init(date: Date = Date(), breadSlices: Int = 0, teaGlasses: Int = 0) {
        self.date = date
        self.breadSlices = breadSlices
        self.teaGlasses = teaGlasses
    }
}
