//
//  Provider.swift
//  SofraWidgetExtension — TimelineProvider reading from shared App Group UserDefaults.
//
//  Default reload: every 30 minutes (safety net). The main app triggers
//  immediate reloads via WidgetCenter.shared.reloadAllTimelines() after
//  every data mutation (log, counter change, scenePhase .active).
//

import WidgetKit

/// A single timeline entry holding the precomputed daily summary.
struct DailyEntry: TimelineEntry {
    let date: Date
    let summary: WidgetDailySummary
}

struct Provider: TimelineProvider {

    // MARK: - Placeholder (widget gallery while loading)

    func placeholder(in context: Context) -> DailyEntry {
        DailyEntry(date: Date(), summary: .empty)
    }

    // MARK: - Snapshot (widget gallery preview)

    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        let entry = DailyEntry(date: Date(), summary: WidgetDataStore.load())
        completion(entry)
    }

    // MARK: - Timeline (live widget on home screen)

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date()
        let summary = WidgetDataStore.load()
        let entry = DailyEntry(date: now, summary: summary)

        // Reload every 30 minutes as a safety net.
        // The main app forces reloads on every data mutation, so this is
        // only a fallback for midnight rollover or extended background.
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: now
        ) ?? now.addingTimeInterval(1800)

        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}
