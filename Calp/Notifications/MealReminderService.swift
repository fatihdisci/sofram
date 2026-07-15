//
//  MealReminderService.swift
//  Calp — user-controlled local notifications (SF-EX06 / EX07 / EX08).
//
//  Three opt-in, non-nagging notification kinds, all off by default:
//   • Meal reminders  (SF-EX06): gentle nudges at user-set breakfast/lunch/
//     dinner/snack times; a meal's nudge is skipped once that meal is logged.
//   • No-log reminder (SF-EX07): if nothing at all was logged today, a single
//     evening nudge — never sent once anything is logged.
//   • Nightly summary (SF-EX08): an informational recap (calories, protein,
//     logged-meal count); never pushes the user to eat more.
//
//  Design: we never rely on repeating triggers (which can't skip "already
//  logged" days). Instead we schedule concrete one-shot requests across a short
//  rolling horizon and re-arm the whole set whenever state changes — on app
//  foreground, when a preference changes, and right after a meal is logged.
//  `removeAllPendingNotificationRequests` before each pass keeps the set exact
//  and guarantees "at most one per day / never a duplicate".
//
//  Preferences live in UserDefaults under the `calp.notif.*` keys so both
//  this scheduler and the settings UI read/write the same source of truth.
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Meal slots

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }

    /// Default reminder time (24h) — used until the user picks their own.
    var defaultHour: Int {
        switch self {
        case .breakfast: return 9
        case .lunch:     return 13
        case .snack:     return 16
        case .dinner:    return 20
        }
    }

    /// Hour window [start, end) that counts as "this meal was eaten".
    var windowHours: Range<Int> {
        switch self {
        case .breakfast: return 5..<11
        case .lunch:     return 11..<15
        case .snack:     return 15..<18
        case .dinner:    return 18..<24
        }
    }

    var displayName: String {
        switch self {
        case .breakfast: return String(localized: "Kahvaltı")
        case .lunch:     return String(localized: "Öğle yemeği")
        case .snack:     return String(localized: "Ara öğün")
        case .dinner:    return String(localized: "Akşam yemeği")
        }
    }

    var notificationTitle: String {
        switch self {
        case .breakfast: return String(localized: "Kahvaltı vakti")
        case .lunch:     return String(localized: "Öğle yemeği vakti")
        case .snack:     return String(localized: "Ara öğün vakti")
        case .dinner:    return String(localized: "Akşam yemeği vakti")
        }
    }

    /// Neutral, non-accusatory body copy.
    var notificationBody: String {
        String(localized: "Yediysen birkaç saniyede ekleyebilirsin.")
    }

    var enabledKey: String { "calp.notif.meal.\(rawValue).enabled" }
    var hourKey: String    { "calp.notif.meal.\(rawValue).hour" }
    var minuteKey: String  { "calp.notif.meal.\(rawValue).minute" }
    var identifierPrefix: String { "calp.notif.meal.\(rawValue)" }
}

// MARK: - Preferences (UserDefaults-backed, shared with the settings UI)

enum NotificationPrefs {
    static let masterKey = "calp.notif.masterEnabled"

    static let noLogEnabledKey = "calp.notif.nolog.enabled"
    static let noLogHourKey    = "calp.notif.nolog.hour"
    static let noLogMinuteKey  = "calp.notif.nolog.minute"

    static let summaryEnabledKey = "calp.notif.summary.enabled"
    static let summaryHourKey    = "calp.notif.summary.hour"
    static let summaryMinuteKey  = "calp.notif.summary.minute"

    /// One-tap route flag: set when a notification is tapped so the app lands on
    /// the Bugün (daily log) tab.
    static let openDailyKey = "calp.notif.openDaily"

    static let defaultNoLogHour = 21
    static let defaultSummaryHour = 22

    private static var defaults: UserDefaults { .standard }

    private static func intOrDefault(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    // Master

    static var masterEnabled: Bool { defaults.bool(forKey: masterKey) }

    // Meals

    static func mealEnabled(_ slot: MealSlot) -> Bool { defaults.bool(forKey: slot.enabledKey) }
    static func mealTime(_ slot: MealSlot) -> (hour: Int, minute: Int) {
        (intOrDefault(slot.hourKey, slot.defaultHour), intOrDefault(slot.minuteKey, 0))
    }

    // No-log

    static var noLogEnabled: Bool { defaults.bool(forKey: noLogEnabledKey) }
    static var noLogTime: (hour: Int, minute: Int) {
        (intOrDefault(noLogHourKey, defaultNoLogHour), intOrDefault(noLogMinuteKey, 0))
    }

    // Nightly summary

    static var summaryEnabled: Bool { defaults.bool(forKey: summaryEnabledKey) }
    static var summaryTime: (hour: Int, minute: Int) {
        (intOrDefault(summaryHourKey, defaultSummaryHour), intOrDefault(summaryMinuteKey, 0))
    }

    /// True when at least one notification kind is enabled under the master switch.
    static var anyEnabled: Bool {
        guard masterEnabled else { return false }
        if noLogEnabled || summaryEnabled { return true }
        return MealSlot.allCases.contains { mealEnabled($0) }
    }
}

// MARK: - Day coverage (computed from SwiftData)

struct DayCoverage {
    /// Any logged activity today (scans + quick-add tallies) — drives the no-log gate.
    let loggedCount: Int
    /// Meal slots that already have a log in their time window.
    let coveredSlots: Set<MealSlot>
    let calories: Double
    let protein: Double
    /// Number of logged meal events (ScanEntry count) today.
    let mealCount: Int
}

// MARK: - Service

@MainActor
final class MealReminderService {

    static let shared = MealReminderService()
    private init() {}

    private let horizonDays = 4

    /// Ask for notification permission (used when the user first enables a
    /// notification). Returns whether notifications may be shown.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// Recompute today's state and re-arm the whole notification set. Safe to
    /// call often; it fully replaces any previously scheduled requests.
    func reschedule(modelContext: ModelContext) {
        let coverage = computeCoverage(modelContext: modelContext)
        Task { await performReschedule(coverage: coverage) }
    }

    // MARK: Scheduling

    private func performReschedule(coverage: DayCoverage) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard NotificationPrefs.anyEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)

        for dayOffset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let isToday = dayOffset == 0

            // Meal reminders — skip a slot today once it's already been logged.
            for slot in MealSlot.allCases where NotificationPrefs.mealEnabled(slot) {
                if isToday && coverage.coveredSlots.contains(slot) { continue }
                let (h, m) = NotificationPrefs.mealTime(slot)
                guard let fire = fireDate(hour: h, minute: m, on: day, calendar: cal), fire > now else { continue }
                await add(center,
                          id: "\(slot.identifierPrefix).\(dayOffset)",
                          title: slot.notificationTitle,
                          body: slot.notificationBody,
                          fire: fire, calendar: cal)
            }

            // No-log reminder — one evening nudge on a day with nothing logged.
            if NotificationPrefs.noLogEnabled {
                let alreadyLoggedToday = isToday && coverage.loggedCount > 0
                if !alreadyLoggedToday {
                    let (h, m) = NotificationPrefs.noLogTime
                    if let fire = fireDate(hour: h, minute: m, on: day, calendar: cal), fire > now {
                        await add(center,
                                  id: "calp.notif.nolog.\(dayOffset)",
                                  title: String(localized: "Bugünü kaçırma"),
                                  body: String(localized: "Bugün henüz bir şey eklemedin. Hazırsan birkaç saniyede ekleyebilirsin."),
                                  fire: fire, calendar: cal)
                    }
                }
            }

            // Nightly summary — informational; today carries real numbers, future
            // days a neutral prompt (their totals aren't known yet, re-armed daily).
            if NotificationPrefs.summaryEnabled {
                let (h, m) = NotificationPrefs.summaryTime
                if let fire = fireDate(hour: h, minute: m, on: day, calendar: cal), fire > now {
                    let body = isToday
                        ? summaryBody(for: coverage)
                        : String(localized: "Bugünün özetine göz at.")
                    await add(center,
                              id: "calp.notif.summary.\(dayOffset)",
                              title: String(localized: "Günün özeti"),
                              body: body,
                              fire: fire, calendar: cal)
                }
            }
        }
    }

    private func summaryBody(for coverage: DayCoverage) -> String {
        let kcal = Int(coverage.calories.rounded())
        let protein = Int(coverage.protein.rounded())
        let meals = coverage.mealCount
        return String(localized: "Bugün \(kcal) kcal · \(protein) g protein · \(meals) öğün.")
    }

    private func fireDate(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private func add(_ center: UNUserNotificationCenter,
                     id: String, title: String, body: String,
                     fire: Date, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: Coverage

    private func computeCoverage(modelContext: ModelContext) -> DayCoverage {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else {
            return DayCoverage(loggedCount: 0, coveredSlots: [], calories: 0, protein: 0, mealCount: 0)
        }

        let scans = ((try? modelContext.fetch(FetchDescriptor<ScanEntry>())) ?? [])
            .filter { $0.timestamp >= today && $0.timestamp < tomorrow }

        var covered: Set<MealSlot> = []
        for scan in scans {
            let hour = cal.component(.hour, from: scan.timestamp)
            for slot in MealSlot.allCases where slot.windowHours.contains(hour) {
                covered.insert(slot)
            }
        }

        let calories = scans.reduce(0.0) { $0 + $1.itemsOrEmpty.reduce(0.0) { $0 + $1.calories } }
        let protein = scans.reduce(0.0) { $0 + $1.itemsOrEmpty.reduce(0.0) { $0 + $1.protein } }

        let quickTally = ((try? modelContext.fetch(FetchDescriptor<QuickAddCount>())) ?? [])
            .filter { $0.date >= today && $0.date < tomorrow }
            .reduce(0) { $0 + $1.count }

        return DayCoverage(
            loggedCount: scans.count + quickTally,
            coveredSlots: covered,
            calories: calories,
            protein: protein,
            mealCount: scans.count
        )
    }
}

// MARK: - Notification delegate

/// Presents notifications while the app is foregrounded and, on tap, flags the
/// app to route to the Bugün (daily log) tab.
final class MealReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MealReminderDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        UserDefaults.standard.set(true, forKey: NotificationPrefs.openDailyKey)
    }
}
