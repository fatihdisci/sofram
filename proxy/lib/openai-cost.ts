/**
 * Central OpenAI token pricing and cost math, shared by every endpoint that
 * calls OpenAI (currently api/scan.ts and api/weekly-report.ts). Keeping the
 * prices and the calculation in one module means a price change — or a fix to
 * the cached-token accounting — lands in exactly one place instead of drifting
 * between endpoints.
 *
 * Prices are the official OpenAI standard-tier rates, expressed as integer
 * microusd (1 USD = 1_000_000 microusd) per 1,000,000 tokens, so a computed
 * cost is an exact integer microusd after a single rounding step:
 *
 *   gpt-5-nano   input $0.05   cached input $0.005   output $0.40   (per 1M)
 *   gpt-5-mini   input $0.25   cached input $0.025   output $2.00   (per 1M)
 */

/** OpenAI Chat Completions `usage` object, including the newer detail blocks. */
export interface OpenAIUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;

  prompt_tokens_details?: {
    /** Portion of `prompt_tokens` served from OpenAI's prompt cache. */
    cached_tokens?: number;
  };

  completion_tokens_details?: {
    /** Reasoning tokens — already counted inside `completion_tokens`. */
    reasoning_tokens?: number;
  };
}

export const MODEL_PRICING = {
  "gpt-5-nano": {
    inputMicrousdPerMillion: 50_000,
    cachedInputMicrousdPerMillion: 5_000,
    outputMicrousdPerMillion: 400_000,
  },
  "gpt-5-mini": {
    inputMicrousdPerMillion: 250_000,
    cachedInputMicrousdPerMillion: 25_000,
    outputMicrousdPerMillion: 2_000_000,
  },
} as const;

export type PricedModel = keyof typeof MODEL_PRICING;

/** Coerce any token count to a safe non-negative integer. Negative, NaN,
 *  Infinity, and undefined all collapse to 0, so a malformed usage object can
 *  never produce a negative or NaN cost. */
export function nonNegativeInteger(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.floor(value))
    : 0;
}

export interface TokenBreakdown {
  /** Total input tokens OpenAI billed (cached + uncached). */
  promptTokens: number;
  /** Output tokens, which already include any reasoning tokens. */
  completionTokens: number;
  /** Portion of promptTokens served from OpenAI's prompt cache (cheaper rate). */
  cachedInputTokens: number;
  /** promptTokens minus cachedInputTokens; billed at the full input rate. */
  uncachedInputTokens: number;
  /** Reasoning tokens, surfaced for telemetry only. They are part of
   *  completionTokens and must never be billed a second time. */
  reasoningTokens: number;
}

/** Normalize an OpenAI `usage` object into a safe, fully-derived token split. */
export function tokenBreakdown(usage?: OpenAIUsage): TokenBreakdown {
  const promptTokens = nonNegativeInteger(usage?.prompt_tokens);
  const completionTokens = nonNegativeInteger(usage?.completion_tokens);
  // cached_tokens can, in a malformed payload, exceed prompt_tokens; clamp so
  // the uncached remainder can never go negative.
  const cachedInputTokens = Math.min(
    promptTokens,
    nonNegativeInteger(usage?.prompt_tokens_details?.cached_tokens),
  );
  return {
    promptTokens,
    completionTokens,
    cachedInputTokens,
    uncachedInputTokens: promptTokens - cachedInputTokens,
    reasoningTokens: nonNegativeInteger(
      usage?.completion_tokens_details?.reasoning_tokens,
    ),
  };
}

/**
 * Exact cost of one OpenAI call in integer microusd.
 *
 *   cost = uncached_input × input_price
 *        + cached_input   × cached_input_price
 *        + completion     × output_price
 *
 * Cached input is billed at the (much cheaper) cached rate. Reasoning tokens are
 * already inside `completion_tokens`, so they are NOT added again. An unknown
 * model or missing usage yields 0, and any invalid token value is treated as 0.
 */
export function calculatedCostMicrousd(
  model: string,
  usage?: OpenAIUsage,
): number {
  const pricing = MODEL_PRICING[model as PricedModel];
  if (!pricing || !usage) return 0;

  const { uncachedInputTokens, cachedInputTokens, completionTokens } =
    tokenBreakdown(usage);

  // Keep the numerator an integer (tokens × microusd-per-million) and divide
  // once at the end so the result rounds cleanly to integer microusd.
  return Math.round(
    (uncachedInputTokens * pricing.inputMicrousdPerMillion
      + cachedInputTokens * pricing.cachedInputMicrousdPerMillion
      + completionTokens * pricing.outputMicrousdPerMillion) / 1_000_000,
  );
}
