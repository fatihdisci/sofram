# Phase 3c Notes — Home Screen Widget

Home screen widget showing today's remaining calories. Always free (no Pro gating), mirroring the developer's "Vakit" app widget precedent.

Verified: builds against iOS 26.5 SDK (min iOS 17.0), unsigned simulator. Zero errors, zero warnings.

---

## Architecture

```
Main App                                    Widget Extension
─────────                                  ─────────────────
ResultView.save()                          Provider.getTimeline()
DailyView.saveCounters()                         │
CalpApp.scenePhase(.active)               WidgetDataStore.load()
       │                                         │
       └──► WidgetDataStore.save() ◄─────────────┘
              │                         Shared UserDefaults
              └──► UserDefaults(suiteName: "group.com.fatih.calp")
                         │
                   calp.widget.dailySummary (JSON blob)
```

**Data-sharing approach:** App Group UserDefaults with a precomputed Codable struct.  
**Why not SwiftData in the widget:** WidgetKit timeline providers are short-lived processes. ModelContext setup overhead is wasted; CloudKit sync in a widget context is unreliable. UserDefaults with App Groups is the most battle-tested WidgetKit data-sharing pattern. The data payload is tiny (a few numbers).

---

## File structure

### New: shared data layer (both targets)
```
Calp/Models/
  WidgetDailySummary.swift    Codable contract: calories, target, macros, counters, progress, remaining
  WidgetDataStore.swift       Static save()/load() via shared UserDefaults (pure Foundation)
```

### New: main-app-only convenience
```
Calp/Extensions/
  WidgetDataStore+MainApp.swift   saveCurrentDaySummary(modelContext:calorieTarget:)
                                  Queries SwiftData, builds summary, saves, reloads timelines.
                                  Imports SwiftData + WidgetKit. Widget target excluded.
```

### New: widget extension target (CalpWidgetExtension)
```
CalpWidget/
  CalpWidget.swift              @main WidgetBundle — static config, systemSmall + systemMedium
  Provider.swift                 TimelineProvider, 30-min default reload
  WidgetEntryView.swift          Small (ring + remaining) and Medium (ring + macros + counters) layouts
  Extensions/
    Color+Widget.swift           Minimal Color.tokenName accessors (shared Assets.xcassets)
    Font+Widget.swift            Minimal Font.calpXxx aliases (system fonts)
  Info.plist                     WidgetKit NSExtension type
  CalpWidget.entitlements       App Group only (no CloudKit needed)
```

### Modified files
```
project.yml                     Added CalpWidgetExtension target + dependency
Calp/Calp.entitlements        Added App Group key
Calp/Info.plist                Added CFBundleURLTypes (calp:// scheme)
Calp/App/CalpApp.swift        scenePhase observer → catch-up widget update on foreground
Calp/App/ContentView.swift     .onOpenURL handler → navigate to .daily on widget tap
Calp/Views/Result/ResultView.swift   WidgetDataStore.saveCurrentDaySummary() after log
Calp/Views/Daily/DailyView.swift     WidgetDataStore.saveCurrentDaySummary() after counter change
```

---

## Timeline strategy

| Trigger | Mechanism | When |
|---|---|---|
| User taps "Logla" (ResultView) | `saveCurrentDaySummary()` + `reloadAllTimelines()` | Synchronous after SwiftData save |
| Bread/tea counter tap (DailyView) | `saveCurrentDaySummary()` in `saveCounters()` | After counter onChange |
| App becomes active | `saveCurrentDaySummary()` in `scenePhase.onChange` | Every foreground transition |
| Default timeline refresh | `Timeline(entries: [entry], policy: .after(Date(+30min)))` | Every 30 min (safety net) |

---

## Deep link

- Widget applies `.widgetURL(URL(string: "calp://daily")!)` on the root container.
- Main app registers `calp://` scheme via `CFBundleURLTypes` in Info.plist.
- `ContentView.onOpenURL` checks `url.scheme == "calp" && url.host == "daily"` → `nav.goToDaily()`.
- Per `mikro-etkilesimler.md`: the ring is already at the correct value (same precomputed data source), so there is no loading state on the transition.

---

## Visual design trade-offs

1. **No neomorphic shadows.** WidgetKit renders on the home screen wallpaper with system compositing. The dual-tone shadow technique from `Surfaces.swift` would look out of place and is unnecessary in the widget context. Solid `bgPage` background with `containerBackground()` meets system requirements.

2. **Solid accentFill progress arc.** The main app's `CalorieRingView` uses an `AngularGradient` (accentFill → accentFillPressed). In the widget, we use a single solid `accentFill` stroke for simplicity. Widgets are static and don't benefit from multi-stop gradients.

3. **System fonts only.** Geist Sans/Mono is not bundled yet (even in the main app). The widget uses `.system(design: .monospaced)` which matches the fallback behavior in `Font+Tokens.swift`.

4. **No animations.** WidgetKit renders static snapshots. The progress ring is drawn at its computed position with no `withAnimation` wrapper.

5. **Emoji for bread/tea icons** in the medium widget. The `CalpIconView` Shape approach requires the full `CalpIcon.swift` renderer which pulls in the SVG path parser — overkill for 12pt icons in a widget. Standard emoji (🍞, 🍵) are used instead. This is a deliberate simplification; custom icons can be added later if `CalpIcon` shapes are extracted into a shared lightweight module.

---

## Widget sizes

### System Small (160×160)
- Calorie progress ring (110pt, stroke 8pt)
- Center: remaining kcal (display-numeric 36) + "kalan" label
- Bottom: "consumed / target kcal" caption

### System Medium (329×160)
- Left 40%: calorie ring (100pt, scaled-down)
- Right 60%: macro rows (Protein/Carbs/Yağ with colored dots), bread & tea counters, consumed/target caption

---

## Known limitations

1. **Midnight rollover.** The widget shows the previous day's data until either the app becomes active (scenePhase catch-up) or the 30-minute default reload fires. A proactive midnight trigger would require a background task — out of scope for MVP.

2. **CloudKit multi-device sync.** Changes from a second device won't update the widget on the first device until the app on the first device becomes active. The widget reads from local UserDefaults, not CloudKit.

3. **Asset catalog sharing.** The widget target includes `Calp/Assets.xcassets` directly. This means all asset instances (including unused ones) are compiled into the widget bundle. For MVP this is negligible; a production optimization would be a dedicated lightweight widget asset catalog.

4. **No custom widget fonts.** Geist is not bundled. If Geist is added later, the widget's `Font+Widget.swift` needs a corresponding update (or a shared font extension module).

5. **Bread/tea emoji.** The medium widget uses 🍞/🍵 emoji instead of `CalpIconView`. Emoji rendering varies by iOS version. If consistency is critical, extract `CalpIconShape` primitives into a lightweight shared module.

---

## App Store Connect / Provisioning

The App Group `group.com.fatih.calp` must exist in the developer's Apple Developer account:
1. Go to **Certificates, Identifiers & Profiles** → **App Groups** → add `group.com.fatih.calp`.
2. Add the App Group capability to both the **Calp** App ID and the **Calp Widget** App ID.
3. Regenerate provisioning profiles for both targets.

This is a manual developer action — the coding agent cannot perform it.

---

## Verification performed

- `xcodegen generate` → **Created project successfully** (CalpWidgetExtension target included).
- `xcodebuild -scheme Calp -sdk iphonesimulator ... build` → **BUILD SUCCEEDED** — zero errors, zero warnings, both targets.

---

## Future considerations

- **Live Activities / Dynamic Island** — not requested for MVP. Would use the same App Group UserDefaults data source.
- **Widget configuration** (user-selectable display: calories vs macros) — would require `AppIntentTimelineProvider` with a custom Siri intent, significantly more complex. Not needed for MVP.
- **Home Screen Quick Actions** — iOS widget context menu actions (e.g., "Quick Log Tea") could be added without changing the data layer.
- **Lock Screen widget** — `.accessoryCircular` and `.accessoryRectangular` families. Trivial addition: just add the families and a new layout case in WidgetEntryView.
