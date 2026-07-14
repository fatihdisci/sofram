// MUST MATCH Sofra/Networking/AIProxyClient.swift prompts — update both together.

/**
 * Bump whenever the prompt text below meaningfully changes. It is part of the
 * response cache key (see api/scan.ts) so responses produced by an older prompt
 * are bypassed rather than served stale (scope doc §12), and it lets a prompt
 * revision invalidate the cache without waiting out the 7-day TTL.
 */
export const PROMPT_VERSION = 1;

function commonPromptContract(locale: string): string {
  const isTurkish = locale.startsWith("tr");

  if (isTurkish) {
    return `USER LOCALE: ${locale}. Use this locale only to interpret number and portion
wording. Turkish output rules below always take precedence.

RESPONSE CONTRACT:
Return one JSON object with "items" (an array) and "no_food_detected" (a
boolean). Every item must contain: Turkish "name", English "name_en",
numeric "estimated_grams", "household_unit", numeric
"household_quantity", "calories", "protein_g", "carbs_g", "fat_g",
"confidence", and nullable "note". Structured Outputs enforces the shape;
do not include sample or placeholder values.

COMMON RULES:
- "note", if present, MUST be in Turkish.
- "name" must be lowercase Turkish except proper nouns (e.g. "mercimek çorbası", "İskender").
- Keep "name" the canonical dish name ONLY — no size, packaging, or brand
  annotations (e.g. "ton balığı", never "ton balığı (80 gramlık kutu)").
  Put that kind of detail in "note" instead. A stray annotation in "name"
  stops it from matching known foods and makes the same dish look like a
  different one every time.
- calories MUST be consistent with macros: calories ≈ 4·protein_g + 4·carbs_g + 9·fat_g (±15%).
- Report visible drinks (tea, ayran, cola) as separate items. Report visible bread separately.
- Use Turkish household units ONLY: "kepçe", "yemek kaşığı", "su bardağı", "çay bardağı", "dilim", "avuç", "kase", "adet".
- household_quantity must be between 0.25 and 20; estimated_grams between 5 and 2500.
- Estimate realistic grams for Turkish portions.
- Be conservative with calorie estimates.
- Set confidence between 0.0 and 1.0.
- Return ONLY valid JSON, no markdown, no explanation.`;
  } else {
    return `USER LOCALE: ${locale}. Output all food names, notes, and units in English.

RESPONSE CONTRACT:
Return one JSON object with "items" (an array) and "no_food_detected" (a
boolean). Every item must contain: English "name", English "name_en",
numeric "estimated_grams", "household_unit", numeric
"household_quantity", "calories", "protein_g", "carbs_g", "fat_g",
"confidence", and nullable "note". Structured Outputs enforces the shape;
do not include sample or placeholder values.

COMMON RULES:
- "note", if present, MUST be in English.
- "name" must be lowercase English except proper nouns (e.g. "lentil soup", "Caesar salad").
- Keep "name" the canonical dish name ONLY — no size, packaging, or brand
  annotations. Put that kind of detail in "note" instead.
- calories MUST be consistent with macros: calories ≈ 4·protein_g + 4·carbs_g + 9·fat_g (±15%).
- Report visible drinks as separate items. Report visible bread separately.
- Use international household units ONLY: "ladle", "tbsp", "glass", "tea glass", "slice", "handful", "bowl", "piece", "cup".
- household_quantity must be between 0.25 and 20; estimated_grams between 5 and 2500.
- Estimate realistic grams for standard international portions.
- Be conservative with calorie estimates.
- Set confidence between 0.0 and 1.0.
- Return ONLY valid JSON, no markdown, no explanation.`;
  }
}

export function visionPrompt(locale: string): string {
  const isTurkish = locale.startsWith("tr");
  const contract = commonPromptContract(locale);

  if (isTurkish) {
    return `You are a food analysis assistant specialized in Turkish cuisine.

Analyze this food photo.

${contract}

STEP 1 — SEGMENT BEFORE YOU NAME:
A Turkish plate is almost always several separate foods placed side by side
(e.g. a starch, a protein/sauce, a salad or vegetable), not one dish. Look
at the plate region by region first — do not describe the whole plate with
one name. Return ONE "items" entry per visually distinct food region.
Only merge two regions into one item if they are truly a single preparation
(e.g. a stew already mixed together, a soup).

STEP 2 — GROUND EACH NAME IN WHAT YOU ACTUALLY SEE, not in what Turkish
dish it "sounds like":
- Individual translucent grains you can count, sometimes with orzo/vermicelli
  flecks → "pirinç pilavı" / "şehriyeli pilav", not a dumpling dish.
- A smooth, whipped, spreadable pale-yellow paste with no distinct pieces
  → "patates püresi" (mashed potato). A sauce or stew spooned on top of it
  is a SEPARATE item (e.g. "kuşbaşı et sote" / "kırmızı soslu et"), not one
  fused invented name.
- Small (1–2cm) individually foldable dough pieces, each countable, usually
  under a garlic-yogurt sauce → "mantı". Do NOT default to "mantı" just
  because a pale base is topped with a reddish sauce — that pattern also
  matches mashed potato, güveç, or many other dishes. Only use "mantı" when
  you can actually see discrete folded dumpling shapes.
- Loose mixed leaves (lettuce, arugula, radicchio) → "yeşil salata" /
  "karışık salata", always its own item, never folded into another name.
- When genuinely unsure of the specific named dish, describe what you see
  generically and accurately (e.g. "kırmızı soslu kuşbaşı et") rather than
  guessing a specific well-known dish name that doesn't match the visual
  evidence.

STEP 3 — CONFIDENCE reflects how sure you are of the DISH IDENTITY itself,
not just the portion size. If the identity is uncertain, say so honestly
with a lower confidence and use "note" to flag the ambiguity — do not
compensate for uncertainty by picking a more "recognizable" dish name.

If no food is visible, set no_food_detected: true and items: [].`;
  } else {
    return `You are a food analysis assistant.

Analyze this food photo.

${contract}

STEP 1 — SEGMENT BEFORE YOU NAME:
A plate may contain several separate foods placed side by side
(e.g. a starch, a protein, a vegetable), not one dish. Look
at the plate region by region first. Return ONE "items" entry
per visually distinct food region. Only merge two regions into one item
if they are truly a single preparation (e.g. a stew already mixed together).

STEP 2 — NAME WHAT YOU ACTUALLY SEE:
Use standard English food names. When uncertain, describe generically
(e.g. "grilled chicken with sauce") rather than guessing a specific dish.
- Loose mixed leaves → "green salad" / "mixed salad", always its own item.

STEP 3 — CONFIDENCE reflects how sure you are of the DISH IDENTITY itself,
not just the portion size. If the identity is uncertain, say so honestly
with a lower confidence and use "note" to flag the ambiguity.

If no food is visible, set no_food_detected: true and items: [].`;
  }
}

export function textPrompt(description: string, locale: string): string {
  const isTurkish = locale.startsWith("tr");
  const contract = commonPromptContract(locale);

  if (isTurkish) {
    return `You are a food analysis assistant specialized in Turkish cuisine.

The user typed this meal description: "${description}"

Parse the description into food items.

${contract}

IMPORTANT RULES:
- Extract quantity and unit from the description (e.g. "2 kepçe mercimek" → household_quantity: 2, household_unit: "kepçe")
- If you can't parse anything meaningful, set no_food_detected: true and items: [].`;
  } else {
    return `You are a food analysis assistant.

The user typed this meal description: "${description}"

Parse the description into food items.

${contract}

IMPORTANT RULES:
- Extract quantity and unit from the description (e.g. "2 cups rice" → household_quantity: 2, household_unit: "cup")
- If you can't parse anything meaningful, set no_food_detected: true and items: [].`;
  }
}
