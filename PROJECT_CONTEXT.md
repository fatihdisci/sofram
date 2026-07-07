# Sofra — Project Context (read this before any implementation work)

## What this app is
A photo-based calorie tracking iOS app positioned around Turkish shared-table ("sofra") food culture, competing against Cal AI / MyFitnessPal by being local-first, Turkish-portion-language-native, and radically transparent on pricing. Working name "Sofra" — may change later, do not hardcode the name deep into identifiers where avoidable (use a neutral bundle id / module name if convenient).

## Non-negotiable architecture constraints
- **No accounts, no login, ever.** No email, no username, no social auth.
- **No Supabase.** No custom backend database for user data.
- **No RevenueCat.** Subscriptions are StoreKit 2 native only (same pattern as the developer's other shipped app "Arvia": ASC Introductory Offers for a 3-day free trial, direct `Product` / `Transaction` API, no third-party subscription SDK).
- **No barcode scanning feature, ever** — not even as a future phase. Do not scaffold for it.
- User data (logs, scans, profile, settings) lives in **SwiftData**, synced via **CloudKit Private Database** (the user's own iCloud account). The app's own server never stores or sees any of this.
- The only thing that touches our server is: an anonymized photo + prompt, sent to a Vercel Edge Function proxy, which calls Gemini Flash vision, cached/rate-limited via Upstash Redis (image-hash cache + IP/device rate limiting). This is a direct architectural copy of the developer's existing "Arvia" AI proxy chain. Nothing is persisted server-side beyond cache/rate-limit keys.
- Free tier abuse prevention: device-level lifetime free-scan counter (3 scans) + rate limiting, no server-side user accounts needed for this.

## Design system
Two reference files define the entire visual language, do not deviate without checking them:
- `design-tokens.json` — colors (light/dark), typography scale, spacing, radius, shadow recipe, motion durations. This is the source of truth for all styling.
- `design-tokens.md` — rationale and SwiftUI usage snippets for the above.
- `mikro-etkilesimler.md` — catalog of micro-interactions (haptics + animation triggers) per user action. Reference this whenever implementing any tappable/loggable interaction.
- 8 custom line icons (SVG, 24x24, single-color `currentColor`, 1.5px stroke): kepce (ladle), tabak (plate), cay-bardagi (tea glass), ekmek-dilimi (bread slice), kase (bowl), tencere (pot), sofra (shared table top-down), kasik (spoon). Convert these to SwiftUI-compatible vector assets (SF Symbols-style custom symbols or Shape-based views) — do not replace with generic SF Symbols like fork.knife.

Design direction name: "Yumuşak Sofra" (Soft Native) — a restrained neomorphism: warm off-white/copper palette, raised surfaces built from a **dual-border technique, not real box-shadow blur** (light-mode: light border top-left `#FFFFFF`, darker border bottom-right `#D0C9B9`; see shadow_recipe in the tokens file for exact SwiftUI `.shadow()` modifier values — it uses two literal `.shadow()` calls with tight radius, not a single soft glow). Text is always high-contrast (see `text-primary` / `text-secondary` — never render text in `accent-fill`, that color is reserved for icons/graphics/button fills only, it fails 4.5:1 as a text color). Typography: Geist Sans (UI) + Geist Mono (all numeric displays — calories, macros, percentages) with tabular figures.

## Turkish portion vocabulary (core product concept)
The AI's raw gram output is always mapped to and editable in Turkish household units: kepçe (ladle), yemek kaşığı (tbsp), su bardağı (glass), çay bardağı (tea glass), dilim (slice), avuç (handful), kase (bowl). Users correct AI results using these units via steppers/pickers, never raw grams or a generic slider.

## MVP scope (this phase and near-term phases)
In scope for MVP: camera-first capture flow, AI scan (Gemini Flash vision via the proxy), text-based logging alternative ("2 kepçe mercimek, 1 dilim ekmek" parsed by AI), Turkish portion dictionary, daily ring (calories + 3 macros), 7-day summary, bread & tea quick counters, onboarding quiz (goal/height/weight/activity → target → paywall), hard paywall via StoreKit 2, home screen widget (today's remaining calories), SwiftData + CloudKit Private sync.

Explicitly NOT in this phase (future versions, do not build now): "Sofra Modu" (multi-item shared-table photo mode), pot/home-recipe calibration memory, Apple Health write integration, Ramadan mode, barcode (never, any phase).

## Developer's working process
Solo iOS developer, uses AI coding agents (you) for all implementation. Claude (a separate assistant) handles analysis, architecture, and prompt writing — never touches code directly. You will receive atomic, phased prompts. Each phase has an explicit scope and an explicit "out of scope" list — respect both boundaries strictly. Ask for clarification rather than assuming when a decision isn't covered by this context or the current phase prompt.
