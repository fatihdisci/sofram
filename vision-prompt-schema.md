# Vision/Text Prompt Contract

This file is the human-readable source contract for the prompts in
`Sofra/Networking/AIProxyClient.swift`. The shared rules below are emitted by
`commonPromptContract(locale:)` into both the photo and text prompts.

## Shared response contract

The response is one JSON object containing:

- `items`: an array of food items.
- `no_food_detected`: a boolean.

Every item contains these required fields:

- `name`: Turkish food name.
- `name_en`: English food name for internal logging.
- `estimated_grams`: numeric gram estimate.
- `household_unit`: one of `kepçe`, `yemek kaşığı`, `su bardağı`,
  `çay bardağı`, `dilim`, `avuç`, `kase`, `adet`.
- `household_quantity`: numeric unit quantity.
- `calories`, `protein_g`, `carbs_g`, `fat_g`: numeric nutrition values.
- `confidence`: numeric confidence.
- `note`: nullable string.

Structured Outputs enforces this shape. Prompts deliberately contain no sample
nutrition numbers or few-shot JSON, avoiding numeric anchoring.

## Shared rules — photo and text

- The supplied user locale is used only to interpret number and portion wording;
  Turkish output rules always take precedence.
- `note`, when present, must be Turkish.
- `name` is lowercase Turkish except proper nouns, for example
  `mercimek çorbası` and `İskender`.
- `name` contains only the canonical dish name. Size, packaging, and brand
  annotations belong in `note`.
- Calories remain within ±15% of
  `4 × protein_g + 4 × carbs_g + 9 × fat_g`.
- Visible drinks such as tea, ayran, and cola are separate items. Visible bread
  is also a separate item.
- Only the Turkish household units listed in the response contract are used.
- `household_quantity` is between 0.25 and 20.
- `estimated_grams` is between 5 and 2500.
- Gram estimates are realistic for Turkish portions and calorie estimates are
  conservative.
- `confidence` is between 0 and 1.
- Output is valid JSON only, without markdown or explanation.

## Photo-only rules

The photo prompt retains the existing three-step behavior:

1. Segment visually distinct food regions before naming them. Merge only foods
   that are genuinely one preparation.
2. Ground names in visible evidence. In particular, distinguish rice grains,
   mashed potato, discrete mantı pieces, sauces/stews, and loose salad leaves.
   When uncertain, prefer an accurate generic description over an invented
   famous dish name.
3. Confidence measures dish identity confidence, not merely portion certainty;
   ambiguity is explained in a Turkish `note`.

If no food is visible, return `items: []` and `no_food_detected: true`.

## Text-only rules

The text prompt extracts the quantity and Turkish household unit from the user’s
description. If nothing meaningful can be parsed, it returns `items: []` and
`no_food_detected: true`.

## Synchronization rule

The proxy prompt planned under SF-201 must copy these same rules. Whenever this
document or `commonPromptContract(locale:)` changes, update the proxy prompt in
the same change.
