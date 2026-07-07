# Phase 3e Notes — Bugfix & Design Overhaul Pass

User-reported issues after 3d: scans always fail, camera screen has no exit/controls,
text-log close behaves unexpectedly, overall UI feels flat/bare. Full root-cause pass
+ redesign of every main screen.

Verified: `xcodebuild -scheme Sofra -sdk iphonesimulator build` → **BUILD SUCCEEDED**,
zero errors, zero warnings, both targets. Simulator-verified screens: onboarding,
daily (redesign), deep-link registration. Camera capture path requires a physical
device (simulator has no camera hardware).

---

## Root causes found

### 1. "Tarama başarısız oldu" — the AI proxy endpoint was never configured
`Info.plist` ships `AIProxyEndpointURL = https://REPLACE-ME.vercel.app/api/scan`.
The Vercel proxy has not been deployed, so **every** photo/text scan failed with the
generic retry message. The camera itself was working — the failure was downstream.

**Fixes:**
- `AIProxyClient.isConfigured` detects the placeholder host and now throws a distinct
  `AIProxyError.notConfigured` with copy that says the server isn't connected
  (instead of implying a transient/camera problem).
- **DEBUG demo mode** (`AIProxyClient.isDemoMode`): while the endpoint is unconfigured,
  debug builds answer scans locally — photo scans rotate 3 realistic Turkish meals,
  text scans do a light "2 kepçe mercimek" quantity+unit parse per comma segment,
  with ~1.4s simulated latency. The whole capture → analysis → result → log flow is
  testable today. The AnalysisOverlay shows a "Demo verisi" pill so it can't be
  mistaken for real inference. **Release builds never fake data.**
- Uploads are downscaled before base64 (`ImageDownscaler`, max 1280px, JPEG 0.7):
  a full-res 12MP capture is ~5–10MB and was going up raw.

**Still required to go live: deploy the proxy and set `AIProxyEndpointURL`.**

### 2. Camera engine races
- `capturePhoto()` invoked `photoOutput.capturePhoto` **before** storing the
  continuation → a fast-failing delegate callback saw a nil continuation and the
  shutter hung forever. Continuation is now registered first, on the session queue.
- A brand-new `AVCaptureSession` was built per screen visit while the previous one
  was still tearing down on a concurrent global queue (screen transitions keep both
  views alive for ~0.4s) → start/stop interleaving, black/frozen previews.
  `CameraManager` is now a single shared instance: configured once, all mutations on
  one serial `sessionQueue`, cheap restarts on re-entry.
- Double-capture overwrite of the pending continuation now rejected
  (`CameraError.captureInProgress`); silent `catch` replaced with an error toast.

### 3. Camera screen had no controls
Added: close (X → daily), torch toggle, tap-to-focus (with focus ring animation,
`captureDevicePointConverted` for accurate metering), viewfinder corner brackets +
"Tabağı çerçeveye al" hint, permission-denied state with an "Ayarlar'ı Aç" deep link,
capture-failure toast. Free-scan badge hidden for subscribers.

### 4. Navigation dead ends
- Text-log close always went to camera. `NavigationModel` now tracks
  `textLogOrigin` (camera|daily) and `closeTextLog()` returns there.
- Text-log input is preserved as `textLogDraft` on the model — backing out of a
  result no longer loses typed text; a successful log clears it.
- Result dismiss is source-aware: photo → camera, text → back to the editor.
- `FreeScanLimitView` had a "Yakında" no-op even though the paywall shipped in 3b —
  now opens `PaywallView` (with a context-appropriate skip label) and got an X back
  to daily (it must never be a dead end). The `.textLog` route is now gated by the
  same free-scan check as `.camera` (both entry points consume the same allowance).
- New deep links (widget / future lock-screen actions): `sofra://camera`,
  `sofra://textlog` alongside `sofra://daily`.

### 5. Portion correction didn't rescale nutrition (ResultView)
Changing "2 kepçe" to "4 kepçe" left calories/macros untouched. `EditableVisionItem`
now keeps the AI estimate as a per-unit baseline and scales grams/kcal/macros with
the corrected quantity. A live totals bar (kcal + P/C/F, numericText transitions)
sits above "Logla".

---

## Design overhaul ("Yumuşak Sofra", applied for real this time)

- **Geist bundled.** Static OTFs (Sans R/M/SB + Mono R/M, MIT, from vercel/geist-font)
  in `Sofra/Resources/Fonts/`, registered via `UIAppFonts`,
  `SofraTypography.geistAvailable = true`. PostScript names verified against
  `Font+Tokens.swift`. Numerals across the app are now true Geist Mono (slashed zeros).
- **DailyView:** time-of-day greeting ("Günaydın/İyi günler/İyi akşamlar") + full
  Turkish date; ring gains consumed/target caption and a neutral over-target state
  ("kcal hedef üstü" — no red/shaming per the micro-interaction philosophy); macro
  cards show progress bars against derived targets (30/40/30 kcal split → g);
  7-day card gains a live sparkline (today = full copper); meal entries grouped per
  scan with time + source icon + entry total and **context-menu delete** (updates
  widget); warm empty-state card with photo/text CTAs.
- **Macro palette:** three new asset colors (`macroProtein` sage, `macroCarb` amber,
  `macroFat` terracotta), light+dark variants, graphics-only per the contrast rules.
- **SevenDaySummaryView:** rebuilt — stats row (avg kcal, total bread, total tea),
  7-bar chart with dashed target line and single-letter day labels, aligned mono
  day rows ("—" for empty days, today highlighted), proper sheet header. Shared day
  math extracted to `DaySummaryBuilder` (used by both the sheet and the sparkline).
- **QuickCounterView:** icon chips on `accentTintBg`, unit labels, "+" affordance,
  long-press to decrement (mis-tap recovery; medium haptic + "-1" ghost) — tap/+1
  ghost behavior unchanged per the catalog.
- **AnalysisOverlay:** viewfinder brackets + sweeping copper beam + rotating status
  captions ("Tabak inceleniyor…" → "Porsiyonlar ölçülüyor…" → "Kaloriler
  hesaplanıyor…"); cancel X during analysis; failures land in a proper bottom card
  (distinct copy for notConfigured vs transient, retry-in-place + Vazgeç).
- **TextLogView:** inset (pressed-surface) editor per the neomorphic language,
  quick-add suggestion chips ("1 çay", "1 simit", …), delayed keyboard focus so the
  screen transition lands first, error alert carries the real reason.
- **ResultView:** text-source results no longer show a blank 44×44 thumbnail; back
  chevron for text (returns to editor), totals bar, empty-state copy per source.

---

## Files added
- `Sofra/Models/DaySummaryBuilder.swift`
- `Sofra/Resources/Fonts/*.otf` (5 files)
- `Sofra/Assets.xcassets/Colors/macro{Protein,Carb,Fat}.colorset`
- Regenerated `Sofra.xcodeproj` via `xcodegen generate`.

## Known follow-ups
- Deploy the Vercel proxy; set `AIProxyEndpointURL` (+ optional `x-sofra-key`).
- Physical-device camera pass (simulator has no camera): torch, tap-to-focus,
  capture latency.
- Onboarding/Paywall visual pass was out of scope this round (functional, tokens
  applied, but not redesigned).
