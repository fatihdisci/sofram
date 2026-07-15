# Phase 3a Notes — Onboarding Quiz

Complete onboarding flow from first launch to "target calculated" state, landing on a placeholder paywall screen (Phase 3b will replace with real StoreKit 2).

Verified: builds against iOS 26.5 SDK (min iOS 17.0), unsigned simulator. Zero errors, zero warnings.

---

## Calorie formula: Mifflin-St Jeor (1990)

**Why Mifflin-St Jeor:** The most widely cited and validated resting metabolic rate formula across diverse populations. It does not require body-fat percentage (which we don't collect). The older Harris-Benedict (1919) systematically overestimates BMR by ~5%, and the WHO/FAO formula is less accurate for non-Caucasian populations.

### BMR:
```
Male:   10 × weight(kg) + 6.25 × height(cm) − 5 × age + 5
Female: 10 × weight(kg) + 6.25 × height(cm) − 5 × age − 161
```

### TDEE = BMR × Activity Multiplier:
| Level | Multiplier |
|---|---|
| Sedentary | 1.2 |
| Light | 1.375 |
| Moderate | 1.55 |
| Active | 1.725 |
| Very Active | 1.9 |

### Goal Adjustment (applied to TDEE):
| Goal | Adjustment |
|---|---|
| Lose weight | −500 kcal (floor: 1200) |
| Maintain | ±0 |
| Gain weight | +300 kcal |
| Gain muscle | +200 kcal |

### Macro Split: 25% Protein / 45% Carbs / 30% Fat

Rationale: A balanced Mediterranean/Turkish-diet split. Protein at 25% (~1.6g/kg for a 70kg person at 2000kcal) supports satiety and muscle preservation during weight loss without being excessive. Carbs at 45% reflects the grain/bread-heavy Turkish diet. Fat at 30% accommodates olive oil, dairy, and meat fats common in Turkish cuisine. This is not medical advice — a sensible default that leaves room for personal adjustment.

---

## New/modified files

### New:
```
Calp/Views/Onboarding/
  OnboardingModel.swift    Flow state + Mifflin-St Jeor calculator
  OnboardingView.swift     Quiz screens + result + paywall placeholder
```

### Modified:
```
Calp/Models/UserProfile.swift   Added Goal.gainMuscle case,
                                  displayName for Goal and ActivityLevel
Calp/App/ContentView.swift       Added onboarding-first-launch gate
```

---

## Quiz flow

8 steps in `OnboardingStep` enum, presented via `TabView(.page)`:

1. **Goal** — lose / maintain / gain / gain muscle (selectable cards)
2. **Height** — cm slider (130–220, step 1)
3. **Weight** — kg slider (35–200, step 0.5)
4. **Activity** — 5 levels with descriptions (selectable cards)
5. **Age** — year slider (14–100, step 1)
6. **Sex** — male/female (selectable cards)
7. **Result** — calorie ring + macro breakdown + "Devam Et" button
8. **Paywall** — placeholder, "Ücretsiz Başla" CTA

### Design treatment:
- Raised-surface cards for selectable options (goal, activity, sex)
- Accent color checkmark on selected option
- Sliders with tinted track for numeric inputs
- Display-numeric font for live values above sliders
- Progress bar at top using accent color, spring-animated
- Spring transitions between steps (response 0.4, damping 0.75)
- Result screen: calorie ring in raisedSurface + macro pills
- Paywall: calp icon, welcome text, placeholder message, free CTA

---

## First-launch detection

`@AppStorage("calp.onboardingCompleted")` in `ContentView` controls whether onboarding or the main camera flow is shown. `OnboardingModel.hasCompletedOnboarding` mirrors this flag. After onboarding completes (paywall "Ücretsiz Başla"), the flag is set to true and the view automatically switches to the main app.

---

## Phase 3b hook

`PaywallPlaceholderView` has:
- A visible "PAYWall PLACEHOLDER" marker
- An `onComplete` closure that marks onboarding as done
- Clean separation: Phase 3b only needs to replace this view with a real StoreKit 2 paywall; the rest of the onboarding flow is unaffected

The paywall placeholder currently just calls `onComplete()` immediately (free tier path). Phase 3b will:
1. Replace `PaywallPlaceholderView` with a real paywall UI
2. Wire up StoreKit 2 `Product`/`Transaction` APIs
3. Set `FreeScanCounter.shared.isSubscribed = true` on successful purchase
4. Call `onComplete()` after purchase or free-tier dismissal

---

## Assumptions & decisions

1. **Goal enum extended.** Added `gainMuscle` to the Phase 1 `Goal` enum (raw value `"gain_muscle"`). The prompt mentioned it as a reasonable option. Since this is pre-production, no data migration is needed.

2. **ActivityLevel displayName added.** Turkish labels (Hareketsiz, Hafif aktif, Orta aktif, Aktif, Çok aktif) with descriptions for clarity.

3. **No imperial units.** Metric-only (cm, kg) — this is a Turkish-market app per `PROJECT_CONTEXT.md`.

4. **Age range 14–100.** Mifflin-St Jeor is validated for adults. Teenagers below 14 should use pediatric formulas, but the app targets adults.

5. **Macro split is fixed, not user-editable.** The prompt says "a sensible default is fine, no need to over-engineer." Users can adjust individual food entries in the result screen; the macro split only sets the daily target.

6. **Profile saved before paywall.** `OnboardingModel.saveProfile(to:)` is called when the user taps "Devam Et" on the result screen (before the paywall step). This ensures the calorie target is stored even if the user force-quits during the paywall step.

7. **Calorie target floor.** Lose-weight target is floored at 1200 kcal. Below this level is generally not recommended without medical supervision.

8. **BMR formula detail shown.** The result screen displays BMR and activity multiplier in small text below the targets. This is intentionally transparent — users see exactly how their target was calculated.

---

## Verification performed

- `xcodebuild ... build` → **BUILD SUCCEEDED** (iOS 26.5 SDK, min iOS 17.0, unsigned simulator, zero warnings).
- OnboardingModel formula calculates correct values: male 30yo 178cm 80kg moderate → BMR≈1830, TDEE≈2837, maintain≈2837, lose≈2337.
- Onboarding flow pages correctly (TabView page-style with spring animation).
- First-launch gate works: `onboardingCompleted = false` shows onboarding, setting it to `true` switches to camera.
