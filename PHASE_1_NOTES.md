# Phase 1 Notes — Project Skeleton + Design Tokens + AI Proxy Client

Buildable foundation for **Sofra**. No feature UI yet (camera, scanning, onboarding,
paywall are later phases) — this is project structure, the SwiftData/CloudKit data
layer, the "Yumuşak Sofra" design-system wiring, and the model-agnostic AI proxy client.

Verified: builds against the iOS 26.5 SDK (min deployment **iOS 17.0**), installs, and
launches on the simulator rendering the placeholder **Sofra** screen (see
"Verification" below). CloudKit private-DB mirroring activates in signed/entitled builds.

---

## How to open / build / run

The Xcode project is generated with **XcodeGen** from `project.yml`. Both `project.yml`
and the generated `Sofra.xcodeproj` are committed, so you can just open the project:

```bash
open Sofra.xcodeproj
```

If you change `project.yml` or add/remove source files, regenerate:

```bash
xcodegen generate
```

Command-line build used to verify this phase (unsigned simulator build):

```bash
xcodebuild -project Sofra.xcodeproj -scheme Sofra -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

**To run on a device / enable real CloudKit sync:** set `DEVELOPMENT_TEAM` in
`project.yml` (or select your team in Xcode → Signing & Capabilities), then regenerate.
The CloudKit capability + the container `iCloud.com.fatih.sofra` must be created in your
Apple Developer account (Xcode's "Signing & Capabilities" will offer to create it).

---

## Project layout

```
Sofra/
  App/            SofraApp.swift (@main, injects the model container), ContentView.swift
  Models/         SwiftData @Model types + PortionUnit
  DesignSystem/   Color+/Font+/Layout/Surfaces/SofraIcon (design-token wiring)
  Networking/     AIProxyClient, VisionResponse (DTOs), FreeScanCounter
  Persistence/    SofraModelContainer (SwiftData + CloudKit private DB)
  Resources/Fonts README.md (Geist drop-in slot)
  Assets.xcassets Colors/ (14 token color sets), AccentColor, AppIcon
  Info.plist, Sofra.entitlements
project.yml       XcodeGen spec
```

---

## 1. SVG → SwiftUI icon approach (**chosen: Shape-based, parsed at runtime**)

The 8 line icons are rendered as **SwiftUI `Shape` views**, not PDF/PNG assets.
`SofraIcon.swift` embeds each icon's geometry *verbatim* (the original SVG `d` path
strings + `<circle>`/`<ellipse>` params) and a tiny built-in SVG-path parser
(`SVGPath`) turns them into a `Path`, which `SofraIconView` strokes (1.5px @ 24pt,
round caps/joins — matching the source SVG attributes).

Why this over converting to PDF vector assets:

- **Exact geometry, zero transcription risk** — the path strings are copied as-is; the
  parser reproduces them. (Verified: the 8 icons were rendered by compiling the *actual*
  shipping `SofraIcon.swift` into a macOS tool and rasterizing — all correct, including
  the `S`-curve reflections in çay bardağı/ekmek dilimi.)
- **True `currentColor`** — tint with `.foregroundStyle(...)`; no template-image plumbing.
- **Crisp at any size**, stroke scales proportionally.
- **Animatable** — later phases need a portion-icon draw-on / fill animation
  (`mikro-etkilesimler.md`: "porsiyon ikonunun 'dolma' animasyonu, fill 0→1"). A `Shape`
  supports `.trim`/stroke animation natively; a rasterized imageset does not.
- **Dependency-free** — no `librsvg`/`cairosvg`/Inkscape needed (none were available),
  and no binary blobs in the repo.

The parser intentionally supports only the commands these icons use: `M/L/H/V/C/S/Z`
(absolute + relative) plus circle/ellipse. No elliptical-arc (`A`) or quadratic (`Q`)
— none appear in the source set. Usage: `SofraIconView(icon: .kepce, size: 28)`.

Icons: `kepce, tabak, cayBardagi, ekmekDilimi, kase, kasik, sofra, tencere`.

---

## 2. AI proxy request / response contract

Transport: **HTTP POST, JSON body, base64-encoded JPEG** (chosen over multipart for
simplicity and to match the assumed Arvia-style proxy). Endpoint is configurable via the
Info.plist key `AIProxyEndpointURL` (placeholder `https://REPLACE-ME.vercel.app/api/scan`
this phase), optional shared secret via `AIProxyAPIKey` → sent as header `x-sofra-key`.

**Request** (`AIProxyRequest`):
```json
{
  "image_base64": "<base64 JPEG bytes>",
  "mode": "photo",          // reserved: "text" for future "2 kepçe mercimek…" logging
  "locale": "tr-TR"
}
```

**Response** (`VisionResponse` — the authoritative Swift mirror of
`vision-prompt-schema.md`, unchanged in shape):
```json
{
  "items": [
    {
      "name": "mercimek çorbası",
      "name_en": "red lentil soup",
      "estimated_grams": 350,
      "household_unit": "kepçe",
      "household_quantity": 2,
      "calories": 220,
      "protein_g": 12,
      "carbs_g": 30,
      "fat_g": 6,
      "confidence": 0.88,
      "note": null
    }
  ],
  "no_food_detected": false
}
```

**Model-agnostic:** the client never names a model. The endpoint is a black box that
returns the shape above. Per `MODEL_RESEARCH.md`, the *backend* proxy (out of scope this
phase) runs a primary → fallback chain (Gemini Flash-Lite → GPT-4.1 mini on
error/refusal) and image-hash caching via Upstash; the client only ever sees a valid
`VisionResponse` or a generic `AIProxyError.scanFailed` (its only user-visible error —
"scan failed, please retry"). Non-2xx, transport errors, and unparseable bodies all map
to `.scanFailed`.

**Free-scan gate** (`FreeScanCounter`, UserDefaults-backed, `@Observable`): lifetime cap
of **3** free scans. `canScanForFree = isSubscribed || usedScans < maxFreeScans`.
`isSubscribed` is a **stub** flag (wired to StoreKit 2 in a later phase). The scan flow
(later phase) checks `canScanForFree` before calling `AIProxyClient.scan(...)` and calls
`recordScan()` on success. Kept standalone (not coupled into the client) per the prompt.

---

## 3. Assumptions & decisions where the prompt/context was ambiguous

1. **Bundle id / CloudKit container.** Proceeded with the blessed placeholder
   `com.fatih.sofra` and container `iCloud.com.fatih.sofra`. Change in `project.yml`,
   `Sofra.entitlements`, and `SofraModelContainer.cloudKitContainerID` if you want a
   different reverse-DNS.

2. **`PortionUnit` is a superset** reconciling two differing lists in the source docs:
   - Phase 1 model spec: `…, gram-fallback` (no `tencere`, no `adet`)
   - `vision-prompt-schema.md` `household_unit` enum: `…, tencere, adet` (no `gram`)
   The enum includes **all** of them (`kepçe, yemek kaşığı, su bardağı, çay bardağı,
   dilim, avuç, kase, tencere, adet, gram`) so any scanned item is representable, with
   `.gram` as the fallback. Raw values equal the API's `household_unit` strings, so
   decoding is a clean 1:1 (`PortionUnit(apiValue:)` → unknown maps to `.gram`).

3. **`LoggedItem` has a few fields beyond the literal prompt list.** The prompt named
   name/unit/quantity/calories/protein/carbs/fat. I also persist `nameEn`,
   `estimatedGrams`, `confidence`, and `note` because they come straight from the vision
   schema and grams are central to the product ("raw gram output is always mapped").
   Nothing was omitted from the prompt's list.

4. **CloudKit config uses `.automatic`, not literal `.private(containerID)`.** Both give
   the **private database** (SwiftData has no public/shared option), and `.automatic`
   derives the container from the entitlement. The reason: `.private(id)` *forces*
   CloudKit setup even when the binary isn't entitled (unsigned simulator/CI, or a user
   who turned iCloud off for the app), and CloudKit then **traps** asynchronously during
   mirroring setup — uncatchable by the `do/catch` around container creation. `.automatic`
   enables CloudKit only when entitled and runs local-only otherwise, so the app always
   launches. (Confirmed: `.private(id)` crash-on-launch on the unsigned sim →
   `.automatic` launches cleanly; a signed build still gets private-DB sync — the CloudKit
   mirroring delegate was observed initializing in the launch logs.) If you specifically
   want the container hard-coded once signing is set up, swap `.automatic` →
   `.private(cloudKitContainerID)`.

5. **CloudKit compatibility rules** followed on every `@Model`: every stored property has
   a default value or is optional; relationships are optional (`ScanEntry.items: [LoggedItem]?`,
   inverse `LoggedItem.scanEntry: ScanEntry?`, cascade delete); no `@Attribute(.unique)`
   (CloudKit forbids it) — `ScanEntry.id` is a plain defaulted `UUID`, uniqueness ensured
   at creation. Enums are `String`-backed `Codable` so they store as CloudKit-friendly
   primitives.

6. **Fonts: system fallback (Geist not bundled).** Per the prompt, the typography scale
   is wired to `.system(...)` with the exact token sizes/weights (mono uses `.monospaced`
   design → tabular figures). Switching to Geist is a documented 3-step drop-in
   (`Sofra/Resources/Fonts/README.md` + flip `SofraTypography.geistAvailable`). No
   network fetch was done, to keep the phase self-contained.

7. **Icons converted, not replaced.** All 8 custom icons are preserved as vector Shapes
   (see §1) — no generic SF Symbols substituted, per PROJECT_CONTEXT.

8. **Tooling: XcodeGen.** Chosen to generate a clean, reviewable `.xcodeproj` from
   `project.yml` (hand-writing pbxproj is error-prone). Both files are committed.

9. **Swift language mode 5** (`SWIFT_VERSION = 5.0`) to avoid Swift 6 strict-concurrency
   churn this phase. **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`), **portrait**.

10. **Info.plist foundation extras** (not feature UI): `NSCameraUsageDescription` /
    `NSPhotoLibraryUsageDescription` (Turkish) for the later camera phase,
    `UIBackgroundModes: remote-notification` for CloudKit sync, and
    `ITSAppUsesNonExemptEncryption = false`.

11. **Motion tokens** (`Layout.Motion`, `Animation.sofraSpring`) are exposed as constants
    only — the actual micro-interactions in `mikro-etkilesimler.md` are out of scope and
    not implemented.

---

## Design-token wiring summary

- **Colors** — all 14 tokens are Color Sets in `Assets.xcassets/Colors` (light+dark),
  generated from `design-tokens.json`. Typed accessors in `Color+Tokens.swift`
  (`Color.bgPage`, `.surfaceRaised`, `.accentFill`, `.textPrimary`, …). `AccentColor`
  set = accent-fill. Usage rule enforced by naming: `accentText` for emphasized
  text/numbers, `accentFill` for fills/icons only (it fails 4.5:1 as text).
- **Typography** — `Font+Tokens.swift`: `.sofraDisplayNumeric/.sofraTitle/.sofraHeading/
  .sofraBody/.sofraLabel/.sofraCaption/.sofraNumericSmall` matching `typography.scale`.
- **Spacing / Radius / Motion** — `Layout.swift` (`Layout.Spacing.*`, `Layout.Radius.*`,
  `Layout.Motion.*`).
- **Shadows** — `Surfaces.swift`: `.raisedSurface()` (two `.drop` shadows) and
  `.pressedSurface()` (two `.inner` shadows, since the recipe's pressed state is inset —
  SwiftUI's `.shadow()` view modifier can't do insets, so ShapeStyle shadows are used).
  Per-mode opacities copied verbatim from `shadow_recipe`; colors are the light/dark
  `borderHighlight`/`borderShadow` assets.
- **Icons** — `SofraIcon.swift` (see §1).

`ContentView` exercises a color token, a font token, `.raisedSurface()`, and the `sofra`
icon together as a compile+render smoke test of the whole design system.

---

## Verification performed

- `xcodebuild … build` → **BUILD SUCCEEDED** (iOS 26.5 SDK, min iOS 17.0, unsigned sim).
- Icon parser validated by rendering the real shipping `SofraIcon.swift` to a PNG contact
  sheet — all 8 icons correct.
- App installed + launched on the iPhone 17 Pro simulator; process stays alive (no
  crash); the placeholder **Sofra** screen renders with the correct bg color, raised
  neomorphic card, copper `sofra` icon, and title/caption typography.
