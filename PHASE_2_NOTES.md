# Phase 2 Notes — Core Flow (Camera → AI → Result → Log)

End-to-end working demo: camera capture / text logging → AI analysis → portion correction → save → daily ring with quick counters + 7-day summary.

Verified: builds against iOS 26.5 SDK (min iOS 17.0), unsigned simulator.

---

## Capture API choice: AVFoundation

**AVFoundation (`AVCaptureSession` + `AVCapturePhotoOutput`)** chosen over `PhotosPicker` / `UIImagePickerController`.

Reasons:
1. **Full control over capture moment** — shutter flash animation (white overlay 60ms fade) and `.impact(light)` haptic are triggered at the exact instant the photo is taken, not after a system picker dismisses.
2. **Direct preview layer access** — the `AVCaptureVideoPreviewLayer` is rendered behind the UI overlay, allowing the shutter flash + analysis overlay to transition seamlessly over the same frame.
3. **Native camera UX** — the app opens straight into a live camera preview, which is the core promise of "camera-first."

Trade-off: AVFoundation requires manual permission handling, session management, and is more code than a picker. The `CameraManager` class encapsulates this behind a clean async API (`capturePhoto() async throws -> Data`).

---

## Screen flow / navigation

State machine via `NavigationModel` (`@Observable`, injected as environment):

```
camera ──capture──> analyzing ──stagger reveal──> result ──log──> daily
camera ──textLog──> (free text) ──API──> result ──log──> daily
daily ──camera button──> camera
daily ──7-day summary──> sheet
```

No tab bar — camera is the root screen per `PROJECT_CONTEXT.md`. Transitions use `Animation.calpSpring` (response 0.4, damping 0.75).

---

## New files added (Phase 2)

```
Calp/
  App/
    NavigationModel.swift          AppScreen enum + flow state
  Views/
    Camera/
      CameraView.swift             AVFoundation preview, capture button, shutter flash
    Analysis/
      AnalysisOverlay.swift        Staggered item reveal (150ms/item, fade+scale 0.9→1)
    Result/
      ResultView.swift             Portion correction screen + "Logla" save
      ResultItemCard.swift         Single item card: unit picker, quantity stepper, macros
    TextLog/
      TextLogView.swift            Free-text meal input → same AI proxy → same result screen
    Daily/
      DailyView.swift              Container: ring + macros + counters + entries + 7-day link
      CalorieRingView.swift        Animated ring (ease-out 500ms arc, no incrementing counter)
      QuickCounterView.swift       Bread & tea counters with +1 ghost text (400ms fade)
      SevenDaySummaryView.swift    Trailing 7-day calories + bread/tea list
    Components/
      LogButton.swift              Animated "Logla" with scale(0.96) + checkmark morph
```

## Modified files

| File | Change |
|---|---|
| `AIProxyClient.swift` | Added `scanText()` method, refactored `AIProxyRequest` to support photo/text modes |
| `ContentView.swift` | Replaced placeholder with navigation state machine |
| `CalpApp.swift` | Injects `NavigationModel` as environment |

---

## Assumptions & decisions

1. **Staggered reveal is simulated client-side.** The API returns all items at once (JSON, not streamed). The client simulates the 150ms-per-item stagger by revealing array elements sequentially with `withAnimation(.spring(...))` and `Task.sleep(150ms)`. The behavior prescribed in `mikro-etkilesimler.md` ("tanınan öğeler tek tek belirir") is honored; the fact that the stagger is client-side rather than server-driven is invisible to the user.

2. **Text log shares the result screen.** `TextLogView` calls the same `AIProxyClient.scanText()` endpoint and navigates to the same `ResultView` — the `source: ScanSource` parameter distinguishes photo vs text in the saved `ScanEntry`. This avoids duplicating the entire result/correction UI.

3. **DailyQuickCounter persistence.** Counters are loaded from SwiftData on `DailyView.onAppear` and saved on every `onChange(of: breadSlices/teaGlasses)`. The counter is keyed by start-of-day date. No unique constraint (CloudKit forbids it); the code fetches-or-creates the row for today.

4. **Calorie target fallback.** Uses `@AppStorage("calp.dailyCalorieTarget")` with a default of 2000 kcal. The real target will come from `UserProfile` after onboarding (Phase 3a).

5. **Free scan gate is enforced in `ContentView`.** When `FreeScanCounter.shared.canScanForFree` is false, `FreeScanLimitView` is shown instead of the camera. The paywall CTA is a placeholder — real StoreKit 2 flow is Phase 3b.

6. **Empty image in text-log result.** When navigating from text log to result, `UIImage()` (blank) is passed as the thumbnail. The header thumbnail renders empty — non-ideal but functional; a dedicated icon or placeholder can be added in polish pass (Phase 3d).

7. **Macro colors.** Protein→green, Carbs→orange, Fat→red. These are chosen for quick visual distinction; they are not from `design-tokens.json` (which defines only the Calp palette). A future design pass may replace them with desaturated versions that fit the "Yumuşak Calp" aesthetic better.

8. **7-day summary uses Turkish weekday abbreviations.** `DateFormatter` with `tr_TR` locale, short weekday names (Pzt, Sal, Çar...). "Bugün" and "Dün" labels for the most recent two days.

9. **No animation for ring number.** Per `mikro-etkilesimler.md`: "halka değeri sayı sayarak artmaz, tek yumuşak arc animasyonuyla yeni değere gider." The remaining-calorie number uses `.animation(.none, value: remaining)` — it jumps to the new value while the arc animates smoothly.

---

## Not yet implemented (intentionally deferred)

These are listed in the Phase 2 prompt as out of scope, confirmed here for clarity:

- Onboarding quiz (Phase 3a)
- Paywall / StoreKit 2 (Phase 3b) — free scan limit placeholder only
- Home screen widget (Phase 3c)
- Calp Modu / pot calibration / Apple Health / barcode
- Final animation polish pass (Phase 3d) — only interactions explicitly listed in the Phase 2 prompt are built

---

## Verification performed

- `xcodebuild ... build` → **BUILD SUCCEEDED** (iOS 26.5 SDK, min iOS 17.0, unsigned simulator, zero warnings).
- All 8 new view files + NavigationModel + modified files compile and link correctly.
- App launches on iPhone 17 Pro simulator; camera permission prompt appears (AVCaptureDevice authorization); placeholder free-scan-limit screen renders if counter is exhausted.

---

## How to test end-to-end

Since the AI proxy endpoint is a placeholder (`https://REPLACE-ME.vercel.app/api/scan`), real API calls will fail gracefully with "Tarama başarısız oldu" error. To test the UI flow without a backend:

1. The camera → capture → shutter flash → analysis → error → retry flow can be tested directly.
2. The text log → result flow can be tested the same way.
3. The daily ring, quick counters, and 7-day summary work fully with locally-saved `ScanEntry` data (e.g., by manually inserting test entries via a debug button or by temporarily adding sample data in `CalpApp`).

A real backend endpoint is the blocking dependency for the full end-to-end demo.
