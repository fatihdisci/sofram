//
//  SofraWidget.swift
//  SofraWidgetExtension — WidgetBundle entry point.
//
//  Single widget kind: "Günlük Özet" (Daily Summary).
//  Two families: systemSmall (ring + remaining) and systemMedium (ring + macros).
//  No configuration options, no Live Activities.
//

import WidgetKit
import SwiftUI

@main
struct SofraWidgets: WidgetBundle {
    var body: some Widget {
        SofraDailyWidget()
    }
}

struct SofraDailyWidget: Widget {
    let kind = "com.fatih.calorisor.widget.daily"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: Provider()
        ) { entry in
            SofraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Günlük Özet")
        .description("Bugünkü kalori ve makro durumunuz.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
