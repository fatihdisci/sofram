# Calorisor — Visual Differentiation & Polish Audit

Branch: `roadmap` (dev branch `claude/calorisor-visual-polish-5idq85`).
Date: 2026-07-14.

This is a focused differentiation pass, **not** a redesign. The existing design
system (`design-tokens.json`, `Calorisor/DesignSystem/`) and current product
behavior are the source of truth. Nothing about nutrition, persistence,
StoreKit, scan/text/manual/edit/save flows changes.

> Build note: this working copy is Linux-only — no `swift`, `xcodegen` or
> `xcodebuild` toolchain is present, so the app/widget build and the test suite
> must be run on a Mac. All source changes are written to be picked up by
> `project.yml`'s existing `path: Calorisor` / `path: CalorisorTests` globs; a
> `xcodegen generate` is required before building because the committed
> `.xcodeproj` uses explicit file references (only the icon test file is new —
> every app-facing change lands in an already-referenced file, so the app target
> itself still builds from the committed project).

---

## A. SF Symbols inventory

Every user-visible `Image(systemName:)` today (grouped, with disposition).

### A.1 Navigation / system convention → KEEP_AS_SYSTEM_SYMBOL

These are universal iOS affordances. Replacing them to "be different" would
hurt usability. Kept verbatim.

| File:line | Symbol | Role |
|---|---|---|
| `App/ContentView.swift:184` | `xmark` | close (free-scan limit) |
| `Views/Analysis/AnalysisOverlay.swift:89` | `xmark` | close |
| `Views/Daily/SevenDaySummaryView.swift:120` | `xmark` | close |
| `Views/TextLog/TextLogView.swift:148` | `xmark` | close |
| `Views/Camera/CameraView.swift:321` | `xmark` | close |
| `Views/Result/ResultView.swift:128` | `chevron.left` / `xmark` | back / close |
| `Views/Daily/DailyView.swift:309` | `chevron.right` | disclosure |
| `Views/History/HistoryView.swift:124` | `chevron.right` | disclosure |
| `Views/Onboarding/OnboardingView.swift:99,122` | `chevron.left/right` | wizard nav |
| `Views/Onboarding/OnboardingView.swift:185,293,373` | `checkmark.circle.fill` | selection state |
| `Views/Onboarding/OnboardingView.swift:364` | `figure.stand` / `figure.stand.dress` | biological sex (Apple standard) |
| `Views/Onboarding/OnboardingView.swift:435` | `info.circle.fill` | info |
| `Views/Result/ResultItemCard.swift:63` | `xmark.circle.fill` | remove item (destructive) |
| `Views/Result/ResultItemCard.swift:83` | `info.circle.fill` | shared-pot note |
| `Views/Result/ResultItemCard.swift:154,184` | `minus` / `plus` | quantity stepper |
| `Views/Daily/QuickCounterView.swift:44,85,200,211` | `plus`, `plus.circle`, `minus` | add / counter steppers |
| `Views/TextLog/TextLogView.swift:185` | `plus` | suggestion chip |
| `Views/Camera/CameraView.swift:343` | `bolt.fill` / `bolt.slash` | torch |
| `Views/Camera/CameraView.swift:468` | `photo.on.rectangle` | Photos picker (system) |
| `Views/Camera/CameraView.swift:504` | `camera.on.rectangle` | camera-permission illustration |
| `Views/Camera/CameraView.swift:654` | `camera.fill` / `lock.fill` | 10pt scan-count status badge |
| `App/ContentView.swift` Settings rows | `globe`, `square.and.arrow.up`, `envelope`, `hand.raised`, `doc.text` | settings list rows |
| `Views/Components/LogButton.swift:65,88` | `checkmark` | log confirmation + morph |
| `Views/Components/LogButton.swift:69` | `arrow.down.doc.fill` | "Logla" — see note ↓ |
| `Views/Analysis/AnalysisOverlay.swift:168,217-226` | `wifi.slash`, `clock.fill`, `server.rack`, `antenna.radiowaves.left.and.right.slash`, `wifi.exclamationmark` | network/error status |

**LogButton `arrow.down.doc.fill` (kept):** the button morphs this icon into a
`checkmark` via `.contentTransition(.symbolEffect(.replace))` — a functional,
spec-required micro-interaction (`mikro-etkilesimler.md`: "buton ikonunun
checkmark'a morph olması"). `symbolEffect` only works between two SF Symbols, so
its pre-state sibling stays an SF Symbol. It also carries the literal text
"Logla", so the icon is not load-bearing. Replacing it would break the morph for
zero legibility gain.

### A.2 Core product action → REPLACE_WITH_CALORISOR_ICON

Product-defining actions, replaced with the custom family **where rendered at a
size the 1.5px line family stays legible (≥16pt)**. See the legibility policy in
A.5.

| File:line | Symbol | → | Rendered at |
|---|---|---|---|
| `Views/Daily/DailyView.swift:208` | `camera.fill` | `.capture` | 18pt (hero capture bar) |
| `Views/Daily/DailyView.swift:229` | `text.alignleft` | `.mealNote` | 18pt (text-log affordance) |
| `Views/Camera/CameraView.swift:454` | `camera.fill` | `.capture` | 26pt (shutter) |

### A.3 Product empty / no-result state → REDRAW_AS_CUSTOM_SHAPE

| File:line | Symbol | → |
|---|---|---|
| `Views/Daily/DailyView.swift:379` | brand-icon breathing fallback | `.emptyPlate` static composition (also removes a Reduce-Motion violation, see B) |
| `Views/Result/ResultView.swift:168` | `photo.badge.exclamationmark` (48pt) | `.emptyPlate` |

`SevenDaySummaryView`, `HistoryView`, `CameraView.cardPlaceholder` empty states
already use the custom `.tabak` icon — left as-is.

### A.4 AI-cliché decoration → REMOVE_DECORATION

| File:line | Symbol | Action |
|---|---|---|
| `Views/Onboarding/PaywallView.swift:137` | `sparkles` | **Removed.** `sparkles` is an explicitly banned generic-AI cliché. Replaced with the SF Symbol `target` (accuracy/"isabet"), which is honest about what Pro buys (a stronger vision model → more accurate recognition) and is not a cliché. |

### A.5 Status / source badges → KEEP_AS_SYSTEM_SYMBOL (restrained), one swap

Source-transparency and status badges render at **10–12pt**, below the custom
family's legibility floor (a 1.5px line at 10pt collapses). They stay SF Symbols,
but:

- `Views/Result/ResultItemCard.swift:236` verified badge: `checkmark.seal.fill`
  → `checkmark.circle` (see rationale). A **seal** reads as an official /
  medical certification, which the brief forbids ("Do not make trusted data look
  like an official medical certification"). A plain check in a circle is
  restrained. The badge already pairs **icon + text** ("Doğrulanmış" /
  "Emin değilim") in a single `accentText` tone, so source is never signalled by
  colour alone — that contract is preserved.
- `App/ContentView.swift:378` "Calorisor Pro" active row: `checkmark.seal.fill`
  → `checkmark.circle.fill` for the same "not a certification seal" reason.
- Low-confidence flags (`exclamationmark.triangle.fill` at
  `ResultItemCard.swift:237`, `AnalysisOverlay.swift:322`) are kept — a warning
  triangle is a genuine, universal "heads-up" and is not a source-of-truth claim.

### A.6 Meal-source micro-labels (`DailyView.MealEntryCard`, 10pt) → KEEP

`sourceIcon` (`camera.fill` / `text.alignleft` / `square.and.pencil`, rendered at
10pt, `DailyView.swift:568-580`) and the `FreeScanBadge` (10pt) label provenance
at micro size. Custom line icons collapse here; kept as SF Symbols by the same
≥16pt policy. `DailyView` "Elle gir" (`square.and.pencil`, 11pt) kept likewise.

---

## B. Lottie audit

- **Declared:** `project.yml:34-36` (`airbnb/lottie-spm`, `branch: main`) and as a
  target dependency (`project.yml:75-76`).
- **Wrapper:** yes — `Views/Components/CalorisorLottieView.swift` (`import Lottie`,
  bundle lookup + SwiftUI placeholder fallback).
- **Animation assets:** **none.** `Calorisor/Resources/Animations/` contains only
  `.gitkeep` + `README.md` (the README lists four *expected* `.json` names, all
  unchecked). The only `.json` in the app is `Resources/turkish_food_reference.json`
  (nutrition data, unrelated).
- **Consumers:** exactly one — `DailyView.swift:379`, the "no meals today" empty
  state, calling `CalorisorLottieView("sofra_empty_plate", …)`. Because the asset
  is absent, this has **always** rendered the fallback, never Lottie.

**Verdict: integrated but effectively unused (asset-pending).** The package
compiles (the wrapper imports it) but renders no animation anywhere.

**Decision — Path B (keep declared + document), with the dead call site fixed.**

Removing the SPM package would require hand-editing the committed
`Calorisor.xcodeproj/project.pbxproj` package references (no `xcodegen` available
here to regenerate it safely), which is exactly the kind of package-resolution
churn the acceptance criteria warn against doing blind. So Lottie stays declared,
the `CalorisorLottieView` wrapper is retained as the **single documented future
integration point**, and its wrapper header + the Animations `README.md` already
specify the exact required asset (`sofra_empty_plate.json`, brand line-drawing,
3–5s quiet idle). What changes: the **one** consumer no longer leans on a missing
asset via an always-on breathing fallback. The empty state becomes a purpose-built
static `.emptyPlate` composition (Phase 4), so:

- no screen depends on an absent Lottie file;
- the perpetual `SofraPulseShine` breathing loop (which ran even under Reduce
  Motion, and looped with nothing "genuinely waiting") is gone;
- if/when a brand-approved `sofra_empty_plate.json` is dropped in, re-wiring is a
  one-line change back to `CalorisorLottieView`.

No stock LottieFiles asset is downloaded or invented.

---

## C. Visual consistency audit

Concrete inconsistencies found (file:symbol). Items marked **(fix)** are
addressed in this pass; others are logged for a designer/real-device review.

1. **Icon container treatment is over-uniform.** The circular
   `surfaceRaised`-fill + 42–44pt frame badge is reused for close (`xmark`),
   torch, capture-bar camera and the free-scan-limit brand mark alike
   (`CameraView.topBar`, `ContentView.FreeScanLimitView:199`,
   `DailyView.captureBar:208`). Primary/secondary/status/destructive icons are
   not visually tiered. **(partial fix:** the capture bar's primary action keeps
   its accent-filled circle while the secondary text-log uses a flat bordered
   square — a deliberate primary-vs-secondary split.)
2. **`checkmark.seal.fill` reads as certification** (`ResultItemCard:236`,
   `ContentView:378`). **(fix** → `checkmark.circle[.fill]`).
3. **`sparkles` AI cliché** in the paywall value list (`PaywallView:137`).
   **(fix** → `target`).
4. **Empty-state motion violates Reduce Motion** — `DailyView.emptyMealsCard`
   drives an infinite `SofraPulseShine` breathe with no `accessibilityReduceMotion`
   guard, and loops with nothing pending. **(fix** — static composition).
5. **"Today" distinguished by colour alone in charts.** `WeekSparkline`
   (`DailyView:531`) and `WeekBarChart` (`SevenDaySummaryView:287`) mark today as
   full-opacity accent vs 35% accent. The bar chart already reinforces with a
   `textPrimary` vs `textMuted` label, but the compact sparkline has no non-colour
   cue. **(fix** — add a small non-colour "today" tick under the sparkline's last
   bar; keep the over-target tail neutral, which it already is).
6. **Capture icon inconsistency across the app.** The same "take a photo of your
   meal" action is `camera.fill` at 18pt (daily), 26pt (shutter), 13pt (empty
   state) and 10pt (badge). **(partial fix** — unify the ≥16pt ones to `.capture`;
   the sub-16pt ones stay SF by the legibility policy, documented).
7. **Stroke weight of the custom family is fixed at 1.5px/24** and scales
   linearly (`CalorisorIconView.lineWidth`). Verified the new icons keep the same
   `lineWidth` contract so they sit next to `.tabak`/`.kepce` without weight drift.
8. **Dark mode:** all colours resolve through asset-catalog tokens
   (`Color+Tokens.swift`); no raw hex in views. New icons inherit
   `.foregroundStyle`, so they are automatically light/dark correct. No fix needed.
9. **Dynamic Type / small iPhone:** icon frames are fixed-point (not Dynamic-Type
   scaled) while their paired text scales — acceptable for control glyphs, but the
   capture bar text (`DailyView:213`) is `lineLimit(1)`; on the smallest width at
   AX sizes it truncates. Logged for real-device review (not changed — layout
   behaviour, out of scope for an icon pass).
10. **Tab bar** (`ContentView.tabBarImage`) renders custom icons at `size: 24`,
    `renderer.scale = 3`, `.alwaysTemplate`. Verified no stroke-collapse concern at
    tab scale; left unchanged per the brief (keep native `TabView`).

---

## D. Icons to add (audit-derived, not from the example list)

Only icons with a real ≥16pt consumer on a **current** screen are added:

| Icon | Metaphor | Consumers (≥16pt) |
|---|---|---|
| `.capture` | camera body whose lens is a plate (double circle, echoing `.tabak`) | daily capture bar 18pt; camera shutter 26pt |
| `.mealNote` | note/menu card with lines (text meal logging) | daily text-log affordance 18pt |
| `.emptyPlate` | plate rim with an empty centre line (nothing logged) | daily empty meals 44pt; result no-food 48pt |

Explicitly **not** added (no legible consumer / not implemented):
`voice/waveform` (voice entry is not implemented — Phase 3 says add primitives
only, so nothing is added), `target/verified/approximate` as custom shapes (only
≤12pt consumers, where the 1.5px line collapses — handled with restrained SF
Symbols instead), `notification/reminder` (no such screen exists).

A DEBUG-only icon gallery preview (`#Preview`) covers the full catalog at
18/24/32pt over light & dark, in primary/muted/accent tints. It is a preview
only — never user-facing navigation.
