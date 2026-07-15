//
//  CalpWidget.swift
//  CalpWidgetExtension — WidgetBundle entry point.
//
//  Single widget kind: "Günlük Özet" (Daily Summary).
//  Two families: systemSmall (ring + remaining) and systemMedium (ring + macros).
//  No configuration options, no Live Activities.
//

import WidgetKit
import SwiftUI
import AppIntents

@main
struct CalpWidgets: WidgetBundle {
    var body: some Widget {
        CalpDailyWidget()
    }
}

struct CalpDailyWidget: Widget {
    let kind = "com.fatih.calp.widget.daily"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: Provider()
        ) { entry in
            CalpWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Günlük Özet")
        .description("Bugünkü kalori ve makro durumunuz.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct AddFrequentMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Sık eklenen öğünü ekle"
    static var description = IntentDescription("Seçili sık eklenen öğünü AI çağrısı yapmadan bugüne ekler.")
    static var openAppWhenRun = false

    @Parameter(title: "Öğün")
    var mealID: String

    init() {}

    init(mealID: String) {
        self.mealID = mealID
    }

    func perform() async throws -> some IntentResult {
        guard let meal = WidgetDataStore.load().frequentMeals.first(where: { $0.id == mealID }) else {
            return .result()
        }
        WidgetDataStore.enqueueFrequentMeal(meal)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
