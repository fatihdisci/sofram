import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";
import { textPrompt, visionPrompt, PROMPT_VERSION } from "../prompts.js";
import { resolveEntitlement } from "../lib/entitlement.js";
import {
  calculatedCostMicrousd,
  tokenBreakdown,
  type OpenAIUsage,
} from "../lib/openai-cost.js";
import { recordOpenAICost } from "../lib/metrics.js";

export const config = {
  runtime: "edge",
};

type ScanMode = "photo" | "text";
type Tier = "free" | "pro";

interface ScanRequest {
  image_base64?: string;
  text?: string;
  mode: ScanMode;
  locale: string;
  tier: Tier;
  signed_transaction_info?: string;
  schema_version: number;
  app_version: string;
  input_source?: "photo" | "typed_text" | "voice_transcript";
}

interface OpenAIChatResponse {
  choices?: Array<{
    message?: {
      content?: string | null;
    };
  }>;
  usage?: OpenAIUsage;
}

interface RequestTelemetry {
  requestID: string;
  startedAt: number;
  /** Redis response-cache outcome — NOT OpenAI's prompt cache. A "hit" is served
   *  entirely from Redis with no OpenAI call, so usage/cost stay zero. */
  cacheStatus: "hit" | "miss";
  redisLookupTimeMs: number;
  openAIResponseTimeMs: number;
  /** The OpenAI model this request used (nano/mini), reported even on a cache
   *  hit since the cache is keyed by model. */
  model: string;
  usage?: OpenAIUsage;
  calculatedCostMicrousd: number;
  verificationFailed?: boolean;
}

function telemetryHeaders(telemetry: RequestTelemetry): Record<string, string> {
  const tokens = tokenBreakdown(telemetry.usage);
  return {
    "x-calp-request-id": telemetry.requestID,
    "x-calp-response-time-ms": String(Math.max(0, Date.now() - telemetry.startedAt)),
    "x-calp-openai-response-time-ms": String(telemetry.openAIResponseTimeMs),
    "x-calp-redis-lookup-time-ms": String(telemetry.redisLookupTimeMs),
    "x-calp-model": telemetry.model,
    "x-calp-input-tokens": String(tokens.promptTokens),
    "x-calp-output-tokens": String(tokens.completionTokens),
    "x-calp-cached-input-tokens": String(tokens.cachedInputTokens),
    "x-calp-reasoning-tokens": String(tokens.reasoningTokens),
    "x-calp-calculated-cost-microusd": String(telemetry.calculatedCostMicrousd),
    // Deprecated alias, kept one release so clients reading the old header keep
    // working; it mirrors x-calp-calculated-cost-microusd exactly.
    "x-calp-estimated-cost-microusd": String(telemetry.calculatedCostMicrousd),
    // Redis response-cache outcome (NOT OpenAI's prompt cache).
    "x-calp-cache": telemetry.cacheStatus,
  };
}

const METRIC_RETENTION_SECONDS = 35 * 24 * 60 * 60;
const REQUEST_LOG_RETENTION_SECONDS = 30 * 24 * 60 * 60;
const REQUEST_LOG_KEY = "calp:request-logs";
// Cost counters (cost:microusd, cost:scan, cost:model:*, cost:mode:*) are NOT
// listed here: they are owned exclusively by recordOpenAICost (lib/metrics.ts)
// so the day's total is aggregated in exactly one place and never double-counted.
const METRIC_NAMES = [
  "requests:total",
  "requests:free",
  "requests:pro",
  "mode:photo",
  "mode:text",
  "source:voice",
  "cache:hit",
  "cache:miss",
  "tokens:input",
  "tokens:cached_input",
  "tokens:output",
  "tokens:reasoning",
  "status:error",
  "rate_limited",
  "verification_failed",
] as const;
type MetricName = (typeof METRIC_NAMES)[number];
const ANOMALY_NAMES = [
  "installation_burst",
  "invalid_key",
  "verification_failure",
  "daily_cost_threshold",
] as const;
type AnomalyName = (typeof ANOMALY_NAMES)[number];

interface MetricsEvent {
  date: string;
  tier?: Tier;
  mode?: ScanMode;
  inputSource?: ScanRequest["input_source"];
  status: "success" | "error";
  error?: "rate_limited" | "subscription_verification_failed" | "error";
  telemetry: RequestTelemetry;
  inputChars: number;
  imageBytes: number;
  itemCount: number;
  averageConfidence: number | null;
  noFoodDetected: boolean | null;
}

function metricKey(date: string, name: MetricName): string {
  return `metrics:${date}:${name}`;
}

function anomalyKey(date: string, name: AnomalyName): string {
  return `metrics:${date}:anomaly:${name}`;
}

function imageByteCount(imageBase64: string | undefined): number {
  if (!imageBase64) return 0;
  const padding = imageBase64.endsWith("==") ? 2 : imageBase64.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor(imageBase64.length * 3 / 4) - padding);
}

function responseMetadata(content: string): Pick<MetricsEvent, "itemCount" | "averageConfidence" | "noFoodDetected"> {
  try {
    const parsed = JSON.parse(content) as {
      items?: Array<{ confidence?: unknown }>;
      no_food_detected?: unknown;
    };
    const confidences = (parsed.items ?? [])
      .map((item) => typeof item.confidence === "number" ? item.confidence : null)
      .filter((value): value is number => value !== null && Number.isFinite(value));
    return {
      itemCount: Array.isArray(parsed.items) ? parsed.items.length : 0,
      averageConfidence: confidences.length === 0
        ? null
        : confidences.reduce((sum, value) => sum + value, 0) / confidences.length,
      noFoodDetected: typeof parsed.no_food_detected === "boolean"
        ? parsed.no_food_detected
        : null,
    };
  } catch {
    return { itemCount: 0, averageConfidence: null, noFoodDetected: null };
  }
}

/** Best-effort observability write. The scan response must stay available if
 * Redis metrics/logging is temporarily unavailable. The payload intentionally
 * contains metadata only: never raw IP, installation ID, image, prompt, text,
 * or model response. */
async function recordMetrics(redis: Redis, event: MetricsEvent): Promise<void> {
  const tokens = tokenBreakdown(event.telemetry.usage);
  const cost = event.telemetry.calculatedCostMicrousd;
  const increments: Array<[MetricName, number]> = [];
  if (event.tier) {
    increments.push(["requests:total", 1]);
    increments.push(event.tier === "free" ? ["requests:free", 1] : ["requests:pro", 1]);
  }
  if (event.mode) increments.push(event.mode === "photo" ? ["mode:photo", 1] : ["mode:text", 1]);
  if (event.inputSource === "voice_transcript") increments.push(["source:voice", 1]);
  increments.push([`cache:${event.telemetry.cacheStatus}`, 1]);
  increments.push(["tokens:input", tokens.promptTokens]);
  increments.push(["tokens:cached_input", tokens.cachedInputTokens]);
  increments.push(["tokens:output", tokens.completionTokens]);
  increments.push(["tokens:reasoning", tokens.reasoningTokens]);
  if (event.status === "error") increments.push(["status:error", 1]);
  if (event.error === "rate_limited") increments.push(["rate_limited", 1]);
  if (event.error === "subscription_verification_failed") increments.push(["verification_failed", 1]);
  const anomalies: Array<[AnomalyName, number]> = [];
  if (event.error === "rate_limited") anomalies.push(["installation_burst", 1]);
  if (event.error === "subscription_verification_failed") anomalies.push(["verification_failure", 1]);
  // NOTE: the daily_cost_threshold anomaly is raised by recordOpenAICost against
  // the cumulative daily total below — never per single request.

  const log = {
    request_id: event.telemetry.requestID,
    timestamp: new Date().toISOString(),
    tier: event.tier ?? null,
    mode: event.mode ?? null,
    model: event.telemetry.model,
    input_source: event.inputSource ?? null,
    status: event.status,
    error: event.error ?? null,
    // Redis response-cache outcome. `cache_status` is kept for backward
    // compatibility; `response_cache_status` is the explicit new name that
    // distinguishes it from OpenAI's prompt cache (openai_cached_input_tokens).
    cache_status: event.telemetry.cacheStatus,
    response_cache_status: event.telemetry.cacheStatus,
    openai_cached_input_tokens: tokens.cachedInputTokens,
    response_time_ms: Math.max(0, Date.now() - event.telemetry.startedAt),
    openai_response_time_ms: event.telemetry.openAIResponseTimeMs,
    redis_lookup_time_ms: event.telemetry.redisLookupTimeMs,
    input_tokens: tokens.promptTokens,
    cached_input_tokens: tokens.cachedInputTokens,
    uncached_input_tokens: tokens.uncachedInputTokens,
    output_tokens: tokens.completionTokens,
    reasoning_tokens: tokens.reasoningTokens,
    calculated_cost_microusd: cost,
    // Deprecated alias kept one release; identical to calculated_cost_microusd.
    estimated_cost_microusd: cost,
    input_chars: event.inputChars,
    image_bytes: event.imageBytes,
    item_count: event.itemCount,
    average_confidence: event.averageConfidence,
    no_food_detected: event.noFoodDetected,
  };

  await Promise.all([
    ...increments.map(([name, amount]) => redis.incrby(metricKey(event.date, name), amount)),
    ...METRIC_NAMES.map((name) => redis.expire(metricKey(event.date, name), METRIC_RETENTION_SECONDS)),
    ...anomalies.map(([name, amount]) => redis.incrby(anomalyKey(event.date, name), amount)),
    ...anomalies.map(([name]) => redis.expire(anomalyKey(event.date, name), METRIC_RETENTION_SECONDS)),
    redis.lpush(REQUEST_LOG_KEY, JSON.stringify(log)),
  ]);
  await Promise.all([
    redis.ltrim(REQUEST_LOG_KEY, 0, 999),
    redis.expire(REQUEST_LOG_KEY, REQUEST_LOG_RETENTION_SECONDS),
  ]);

  // Fold this request's cost into the day's cumulative OpenAI total (shared with
  // weekly reports) and let it raise the daily-cost alarm once per day. A cache
  // hit or a usage-less response costs 0 and needs no aggregation.
  if (cost > 0 && event.mode) {
    await recordOpenAICost(redis, {
      date: event.date,
      costMicrousd: cost,
      buckets: ["scan", `model:${event.telemetry.model}`, `mode:${event.mode}`],
    });
  }
}

async function safeRecordMetrics(redis: Redis, event: MetricsEvent): Promise<void> {
  try {
    await recordMetrics(redis, event);
  } catch {
    // Observability must never turn a valid scan into a user-visible failure.
  }
}

function eventFor(
  body: ScanRequest | undefined,
  telemetry: RequestTelemetry,
  date: string,
  content: string | undefined,
  status: MetricsEvent["status"] = "success",
  error?: MetricsEvent["error"],
): MetricsEvent {
  const metadata = content ? responseMetadata(content) : {
    itemCount: 0,
    averageConfidence: null,
    noFoodDetected: null,
  };
  return {
    date,
    tier: body?.tier,
    mode: body?.mode,
    inputSource: body?.input_source ?? (body?.mode === "photo" ? "photo" : "typed_text"),
    status,
    error: error ?? (telemetry.verificationFailed ? "subscription_verification_failed" : undefined),
    telemetry,
    inputChars: body?.text?.length ?? 0,
    imageBytes: imageByteCount(body?.image_base64),
    ...metadata,
  };
}

interface UpstashInfrastructure {
  redis: Redis;
  /** Shared per-identity abuse ceiling. The per-tier daily quota below is the
   *  primary limit; this only blunts bursts (scope doc §11.4). */
  minuteLimit: Ratelimit;
}

const CACHE_TTL_SECONDS = 7 * 24 * 60 * 60;
/** Daily usage counters live slightly longer than a UTC day so a request near
 *  midnight cannot read a prematurely-expired counter. */
const USAGE_TTL_SECONDS = 48 * 60 * 60;
let upstashInfrastructure: UpstashInfrastructure | undefined;

function getUpstashInfrastructure(): UpstashInfrastructure {
  if (upstashInfrastructure) {
    return upstashInfrastructure;
  }

  const redis = Redis.fromEnv();
  upstashInfrastructure = {
    redis,
    minuteLimit: new Ratelimit({
      redis,
      limiter: Ratelimit.slidingWindow(10, "1 m"),
      prefix: "calp:rate:minute",
    }),
  };
  return upstashInfrastructure;
}

// MARK: - Daily usage quotas (scope doc §11.2 / §11.3)

/** Which daily counter a scan draws from. Photo scans use the photo pool; typed
 *  and voice-transcript text scans share the text pool. */
type UsagePool = "photo" | "text";

interface DailyLimit {
  photo: number;
  text: number;
}

/** Per-tier daily limits, enforced server-side against the installation hash.
 *  Tier is still client-claimed until server-side verification lands (SF-1302). */
const DAILY_LIMITS: Record<Tier, DailyLimit> = {
  free: { photo: 1, text: 2 },
  pro: { photo: 50, text: 100 },
};

/** UTC calendar day ("YYYY-MM-DD"). Client timezones are manipulable, so the
 *  day boundary is always UTC (scope doc §11.5). */
function utcDate(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function usageKey(identityKey: string, pool: UsagePool, date: string): string {
  return `calp:usage:${date}:${identityKey}:${pool}`;
}

/** Remaining-quota response headers for a successful (or blocked) scan (§16). */
function limitHeaders(
  tier: Tier,
  photoUsed: number,
  textUsed: number,
): Record<string, string> {
  const limit = DAILY_LIMITS[tier];
  return {
    "x-calp-tier": tier,
    "x-calp-photo-remaining": String(Math.max(0, limit.photo - photoUsed)),
    "x-calp-photo-limit": String(limit.photo),
    "x-calp-text-remaining": String(Math.max(0, limit.text - textUsed)),
    "x-calp-text-limit": String(limit.text),
  };
}

function dailyLimitResponse(
  pool: UsagePool,
  tier: Tier,
  photoUsed: number,
  textUsed: number,
): Response {
  return Response.json(
    { error: "daily_limit_reached", limit_type: pool, tier, remaining: 0 },
    {
      status: 429,
      headers: {
        "x-calp-cache": "miss",
        ...limitHeaders(tier, photoUsed, textUsed),
      },
    },
  );
}

const visionResponseSchema = {
  name: "vision_response",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            name: { type: "string" },
            name_en: { type: "string" },
            estimated_grams: { type: "number" },
            household_unit: {
              type: "string",
              enum: [
                "kepçe",
                "yemek kaşığı",
                "su bardağı",
                "çay bardağı",
                "dilim",
                "avuç",
                "kase",
                "adet",
                "ladle",
                "tbsp",
                "glass",
                "tea glass",
                "slice",
                "handful",
                "bowl",
                "piece",
                "cup",
              ],
            },
            household_quantity: { type: "number" },
            calories: { type: "number" },
            protein_g: { type: "number" },
            carbs_g: { type: "number" },
            fat_g: { type: "number" },
            confidence: { type: "number" },
            note: { type: ["string", "null"] },
          },
          required: [
            "name",
            "name_en",
            "estimated_grams",
            "household_unit",
            "household_quantity",
            "calories",
            "protein_g",
            "carbs_g",
            "fat_g",
            "confidence",
            "note",
          ],
        },
      },
      no_food_detected: { type: "boolean" },
    },
    required: ["items", "no_food_detected"],
  },
} as const;

function jsonError(
  error: "rate_limited" | "invalid_request" | "unauthorized" | "daily_limit_reached" | "subscription_required" | "subscription_verification_failed" | "upstream_error" | "service_unavailable",
  status: number,
): Response {
  return Response.json(
    { error },
    {
      status,
      headers: { "x-calp-cache": "miss" },
    },
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

const TURKISH_QUANTITY_WORDS: Record<string, string> = {
  bir: "1",
  iki: "2",
  üç: "3",
  dört: "4",
  beş: "5",
  altı: "6",
  yedi: "7",
  sekiz: "8",
  dokuz: "9",
  on: "10",
};

const PORTION_UNITS = new Set([
  "kepçe", "yemek", "su", "çay", "dilim", "avuç", "kase", "adet", "gram",
]);

function normalizedText(value: string): string {
  const words = value
    .normalize("NFKC")
    .toLocaleLowerCase("tr-TR")
    .trim()
    .replace(/\s+/g, " ")
    .split(" ");

  return words.map((word, index) => {
    const nextWord = words[index + 1]?.replace(/[^\p{L}]/gu, "") ?? "";
    return PORTION_UNITS.has(nextWord) && TURKISH_QUANTITY_WORDS[word]
      ? TURKISH_QUANTITY_WORDS[word]
      : word;
  }).join(" ");
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function clientIP(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || request.headers.get("x-real-ip")?.trim() || "unknown";
}

const INSTALLATION_ID_HEADER = "x-calp-installation-id";
// brand-keep: the pre-rename installation-id header is still accepted while
// older debug builds remain in circulation.
const LEGACY_INSTALLATION_ID_HEADER = "x-calorisor-installation-id"; // brand-keep

interface LimitIdentity {
  /** SHA-256 rate-limit key. Never the raw installation UUID or a raw IP. */
  key: string;
  source: "installation" | "ip";
}

/**
 * Resolve the anonymous rate-limit identity for a request.
 *
 * Preferred: `SHA256(installation_id + INSTALLATION_HASH_SALT)` from the
 * `x-calp-installation-id` header — a stable per-install key that survives
 * IP changes and shared networks (scope doc §8.2 / §11.1). The raw UUID is
 * hashed with a server-held salt and is never logged or stored in the clear.
 *
 * Fallback: a hashed client IP, for pre-SF-1102 clients that do not send the
 * header yet (transition window). Callers may reject the missing-header case
 * outright via `REQUIRE_INSTALLATION_ID` once all shipped clients send it.
 */
async function limitIdentity(
  rawInstallationID: string | undefined,
  request: Request,
  salt: string,
): Promise<LimitIdentity> {
  if (isNonEmptyString(rawInstallationID)) {
    return {
      key: await sha256(rawInstallationID + salt),
      source: "installation",
    };
  }
  return { key: await sha256(clientIP(request)), source: "ip" };
}

/** tier → model. The chosen model is part of the cache key so a free (nano)
 *  result is never served to a pro (mini) request or vice versa (scope doc §12). */
function modelForTier(tier: Tier): string {
  return tier === "pro" ? "gpt-5-mini" : "gpt-5-nano";
}

async function cacheKey(forRequest: ScanRequest, model: string): Promise<string> {
  const source =
    forRequest.mode === "photo"
      ? (forRequest.image_base64 ?? "")
      : normalizedText(forRequest.text ?? "");
  const inputHash = await sha256(source);
  // v3 splits the cache by model, locale and prompt version as well as the
  // normalized input, so nano/mini results, per-language prompts, and old prompt
  // revisions can never cross-serve each other. Bump v3 if input normalization
  // itself changes; bump PROMPT_VERSION when the prompt text changes.
  return `calp:scan:v3:${forRequest.mode}:${forRequest.locale}:${model}:${PROMPT_VERSION}:${inputHash}`;
}

function isScanRequest(value: unknown): value is ScanRequest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }

  const body = value as Record<string, unknown>;
  if (
    (body.mode !== "photo" && body.mode !== "text") ||
    (body.tier !== undefined && body.tier !== "free" && body.tier !== "pro") ||
    body.schema_version !== 1 ||
    !isNonEmptyString(body.locale) ||
    !isNonEmptyString(body.app_version)
  ) {
    return false;
  }

  if (body.signed_transaction_info !== undefined &&
      (!isNonEmptyString(body.signed_transaction_info) || body.signed_transaction_info.length > 100_000)) {
    return false;
  }

  if (
    body.input_source !== undefined &&
    body.input_source !== "photo" &&
    body.input_source !== "typed_text" &&
    body.input_source !== "voice_transcript"
  ) {
    return false;
  }

  if (body.mode === "photo") {
    return (
      isNonEmptyString(body.image_base64) &&
      body.text === undefined &&
      /^[A-Za-z0-9+/]+={0,2}$/.test(body.image_base64)
    );
  }

  return (
    isNonEmptyString(body.text) &&
    body.text.length <= 300 &&
    body.image_base64 === undefined
  );
}

function messages(forRequest: ScanRequest): Array<Record<string, unknown>> {
  if (forRequest.mode === "photo") {
    return [
      {
        role: "user",
        content: [
          { type: "text", text: visionPrompt(forRequest.locale) },
          {
            type: "image_url",
            image_url: {
              url: `data:image/jpeg;base64,${forRequest.image_base64}`,
              // Pin the vision detail tier explicitly. "auto" lets OpenAI pick
              // (and change) the tier, which makes image token counts — and so
              // cost — unpredictable and inconsistent between free and pro.
              detail: "high",
            },
          },
        ],
      },
    ];
  }

  return [
    {
      role: "user",
      content: [
        {
          type: "text",
          text: textPrompt(forRequest.text ?? "", forRequest.locale),
        },
      ],
    },
  ];
}

export default async function handler(request: Request): Promise<Response> {
  const telemetry: RequestTelemetry = {
    requestID: crypto.randomUUID(),
    startedAt: Date.now(),
    cacheStatus: "miss",
    redisLookupTimeMs: 0,
    openAIResponseTimeMs: 0,
    model: modelForTier("free"),
    calculatedCostMicrousd: 0,
  };

  if (request.method !== "POST") {
    return jsonError("invalid_request", 400);
  }

  // brand-keep: new CALP_* env wins; the old name is a transition fallback so a
  // not-yet-updated Vercel environment keeps authenticating.
  const clientKey = process.env.CALP_CLIENT_KEY ?? process.env.CALORISOR_CLIENT_KEY; // brand-keep
  // brand-keep: accept the pre-rename request header during the client rollout.
  const presentedClientKey = request.headers.get("x-calp-key")
    ?? request.headers.get("x-calorisor-key"); // brand-keep
  if (!clientKey || presentedClientKey !== clientKey) {
    try {
      await Redis.fromEnv().incrby(anomalyKey(utcDate(), "invalid_key"), 1);
    } catch { /* an alert must not reveal infrastructure state */ }
    return jsonError("unauthorized", 401);
  }

  const openAIKey = process.env.OPENAI_API_KEY;
  if (!openAIKey) {
    return jsonError("service_unavailable", 503);
  }

  // The installation-hash salt is required infrastructure: without it we cannot
  // derive the anonymous rate-limit identity. Fail with a controlled 502 (not an
  // unhandled crash) rather than silently degrading to IP-only limiting or
  // hashing with an empty salt.
  const installationSalt = process.env.INSTALLATION_HASH_SALT;
  if (!installationSalt) {
    return jsonError("service_unavailable", 503);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonError("invalid_request", 400);
  }

  if (!isScanRequest(body)) {
    return jsonError("invalid_request", 400);
  }

  // The client tier is only a legacy Pro claim. The server resolves the real
  // tier from the signed StoreKit transaction below.
  let tier: Tier = "free";
  const pool: UsagePool = body.mode === "photo" ? "photo" : "text";
  let model = modelForTier(tier);

  let infrastructure: UpstashInfrastructure;
  let responseCacheKey: string;
  // Carried out of the try so the post-scan success path can increment the
  // right daily counter and report remaining quota.
  let usageIdentityKey = "";
  let usageDate = "";
  let photoUsed = 0;
  let textUsed = 0;
  try {
    infrastructure = getUpstashInfrastructure();

    // Rate-limit identity is the anonymous installation hash (scope doc §11.1),
    // falling back to a hashed IP for clients that predate the header. Once every
    // shipped build sends it, set REQUIRE_INSTALLATION_ID=true to reject the
    // missing-header case instead of falling back.
    const rawInstallationID = (request.headers.get(INSTALLATION_ID_HEADER)
      ?? request.headers.get(LEGACY_INSTALLATION_ID_HEADER))?.trim();
    if (
      !isNonEmptyString(rawInstallationID) &&
      process.env.REQUIRE_INSTALLATION_ID === "true"
    ) {
      return jsonError("invalid_request", 400);
    }
    const identity = await limitIdentity(rawInstallationID, request, installationSalt);
    usageIdentityKey = identity.key;
    usageDate = utcDate();
    const entitlement = await resolveEntitlement(
      infrastructure.redis,
      identity.key,
      body.signed_transaction_info,
      body.tier === "pro",
    );
    tier = entitlement.tier;
    model = modelForTier(tier);
    telemetry.model = model;
    body.tier = tier;
    telemetry.verificationFailed = entitlement.verificationFailed;
    const photoKey = usageKey(identity.key, "photo", usageDate);
    const textKey = usageKey(identity.key, "text", usageDate);

    // Shared minute abuse limit + today's usage counts in a single round trip.
    const redisStartedAt = Date.now();
    const [minute, usage] = await Promise.all([
      infrastructure.minuteLimit.limit(identity.key),
      infrastructure.redis.mget<(number | null)[]>(photoKey, textKey),
    ]);
    telemetry.redisLookupTimeMs = Date.now() - redisStartedAt;
    if (!minute.success) {
      await safeRecordMetrics(infrastructure.redis, eventFor(body, telemetry, usageDate, undefined, "error", "rate_limited"));
      return jsonError("rate_limited", 429);
    }
    photoUsed = Number(usage[0] ?? 0);
    textUsed = Number(usage[1] ?? 0);

    // A cache hit is free and never consumes quota (scope doc §12), so serve it
    // ahead of the daily-limit gate — with the current remaining counts.
    responseCacheKey = await cacheKey(body, model);
    const cacheReadStartedAt = Date.now();
    const cached = await infrastructure.redis.get<string>(responseCacheKey);
    telemetry.redisLookupTimeMs += Date.now() - cacheReadStartedAt;
    if (isNonEmptyString(cached)) {
      telemetry.cacheStatus = "hit";
      await safeRecordMetrics(infrastructure.redis, eventFor(body, telemetry, usageDate, cached));
      return new Response(cached, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          ...telemetryHeaders(telemetry),
          ...limitHeaders(tier, photoUsed, textUsed),
        },
      });
    }

    // Cache miss → enforce the per-pool daily limit before the paid OpenAI call.
    const used = pool === "photo" ? photoUsed : textUsed;
    if (used >= DAILY_LIMITS[tier][pool]) {
      await safeRecordMetrics(infrastructure.redis, eventFor(body, telemetry, usageDate, undefined, "error"));
      return dailyLimitResponse(pool, tier, photoUsed, textUsed);
    }
  } catch {
    return jsonError("upstream_error", 502);
  }

  let upstream: Response;
  const openAIStartedAt = Date.now();
  try {
    upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: messages(body),
        reasoning_effort: body.mode === "photo" ? "low" : "minimal",
        response_format: {
          type: "json_schema",
          json_schema: visionResponseSchema,
        },
        max_completion_tokens: 2048,
      }),
    });
  } catch {
    return jsonError("upstream_error", 502);
  }
  telemetry.openAIResponseTimeMs = Date.now() - openAIStartedAt;

  if (upstream.status === 429) {
    return jsonError("rate_limited", 429);
  }
  if (!upstream.ok) {
    return jsonError("upstream_error", 502);
  }

  let completion: OpenAIChatResponse;
  try {
    completion = (await upstream.json()) as OpenAIChatResponse;
  } catch {
    return jsonError("upstream_error", 502);
  }

  const content = completion.choices?.[0]?.message?.content;
  if (!isNonEmptyString(content)) {
    return jsonError("upstream_error", 502);
  }

  telemetry.usage = completion.usage;
  telemetry.calculatedCostMicrousd = calculatedCostMicrousd(model, completion.usage);

  try {
    await infrastructure.redis.set(responseCacheKey, content, {
      ex: CACHE_TTL_SECONDS,
    });
  } catch {
    return jsonError("upstream_error", 502);
  }

  // The scan succeeded — consume one unit from the pool now, so a failed or
  // rate-limited request never burns quota. INCR is atomic; the 48h TTL is set
  // on the first write of the UTC day. A counter failure must not fail an
  // otherwise-successful scan, so fall back to the pre-read value + 1.
  let poolUsed = (pool === "photo" ? photoUsed : textUsed) + 1;
  try {
    const key = usageKey(usageIdentityKey, pool, usageDate);
    poolUsed = await infrastructure.redis.incr(key);
    if (poolUsed === 1) {
      await infrastructure.redis.expire(key, USAGE_TTL_SECONDS);
    }
  } catch {
    // Keep the fallback estimate.
  }
  if (pool === "photo") {
    photoUsed = poolUsed;
  } else {
    textUsed = poolUsed;
  }

  await safeRecordMetrics(infrastructure.redis, eventFor(body, telemetry, usageDate, content));

  return new Response(content, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...telemetryHeaders(telemetry),
      ...limitHeaders(tier, photoUsed, textUsed),
    },
  });
}
