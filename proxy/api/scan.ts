import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";
import { textPrompt, visionPrompt } from "../prompts.js";

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
  schema_version: number;
  app_version: string;
}

interface OpenAIChatResponse {
  choices?: Array<{
    message?: {
      content?: string | null;
    };
  }>;
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
      prefix: "calorisor:rate:minute",
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
  return `calorisor:usage:${date}:${identityKey}:${pool}`;
}

/** Remaining-quota response headers for a successful (or blocked) scan (§16). */
function limitHeaders(
  tier: Tier,
  photoUsed: number,
  textUsed: number,
): Record<string, string> {
  const limit = DAILY_LIMITS[tier];
  return {
    "x-calorisor-tier": tier,
    "x-calorisor-photo-remaining": String(Math.max(0, limit.photo - photoUsed)),
    "x-calorisor-photo-limit": String(limit.photo),
    "x-calorisor-text-remaining": String(Math.max(0, limit.text - textUsed)),
    "x-calorisor-text-limit": String(limit.text),
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
        "x-calorisor-cache": "miss",
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
  error: "rate_limited" | "invalid_request" | "upstream_error",
  status: number,
): Response {
  return Response.json(
    { error },
    {
      status,
      headers: { "x-calorisor-cache": "miss" },
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

const INSTALLATION_ID_HEADER = "x-calorisor-installation-id";

interface LimitIdentity {
  /** SHA-256 rate-limit key. Never the raw installation UUID or a raw IP. */
  key: string;
  source: "installation" | "ip";
}

/**
 * Resolve the anonymous rate-limit identity for a request.
 *
 * Preferred: `SHA256(installation_id + INSTALLATION_HASH_SALT)` from the
 * `x-calorisor-installation-id` header — a stable per-install key that survives
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

async function cacheKey(forRequest: ScanRequest): Promise<string> {
  const source =
    forRequest.mode === "photo"
      ? (forRequest.image_base64 ?? "")
      : normalizedText(forRequest.text ?? "");
  // Bump this cache version whenever semantic input normalization changes so
  // old, differently-keyed responses cannot keep producing split results.
  return `calorisor:scan:v2:${forRequest.mode}:${await sha256(source)}`;
}

function isScanRequest(value: unknown): value is ScanRequest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }

  const body = value as Record<string, unknown>;
  if (
    (body.mode !== "photo" && body.mode !== "text") ||
    (body.tier !== "free" && body.tier !== "pro") ||
    body.schema_version !== 1 ||
    !isNonEmptyString(body.locale) ||
    !isNonEmptyString(body.app_version)
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
  if (request.method !== "POST") {
    return jsonError("invalid_request", 400);
  }

  const clientKey = process.env.CALORISOR_CLIENT_KEY;
  if (!clientKey || request.headers.get("x-calorisor-key") !== clientKey) {
    return jsonError("invalid_request", 401);
  }

  const openAIKey = process.env.OPENAI_API_KEY;
  if (!openAIKey) {
    return jsonError("upstream_error", 502);
  }

  // The installation-hash salt is required infrastructure: without it we cannot
  // derive the anonymous rate-limit identity. Fail with a controlled 502 (not an
  // unhandled crash) rather than silently degrading to IP-only limiting or
  // hashing with an empty salt.
  const installationSalt = process.env.INSTALLATION_HASH_SALT;
  if (!installationSalt) {
    return jsonError("upstream_error", 502);
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

  // Tier is client-claimed for now (SF-1302 will verify it). Photo scans draw
  // from the photo pool; typed and voice text scans share the text pool.
  const tier: Tier = body.tier;
  const pool: UsagePool = body.mode === "photo" ? "photo" : "text";

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
    const rawInstallationID = request.headers.get(INSTALLATION_ID_HEADER)?.trim();
    if (
      !isNonEmptyString(rawInstallationID) &&
      process.env.REQUIRE_INSTALLATION_ID === "true"
    ) {
      return jsonError("invalid_request", 400);
    }
    const identity = await limitIdentity(rawInstallationID, request, installationSalt);
    usageIdentityKey = identity.key;
    usageDate = utcDate();
    const photoKey = usageKey(identity.key, "photo", usageDate);
    const textKey = usageKey(identity.key, "text", usageDate);

    // Shared minute abuse limit + today's usage counts in a single round trip.
    const [minute, usage] = await Promise.all([
      infrastructure.minuteLimit.limit(identity.key),
      infrastructure.redis.mget<(number | null)[]>(photoKey, textKey),
    ]);
    if (!minute.success) {
      return jsonError("rate_limited", 429);
    }
    photoUsed = Number(usage[0] ?? 0);
    textUsed = Number(usage[1] ?? 0);

    // A cache hit is free and never consumes quota (scope doc §12), so serve it
    // ahead of the daily-limit gate — with the current remaining counts.
    responseCacheKey = await cacheKey(body);
    const cached = await infrastructure.redis.get<string>(responseCacheKey);
    if (isNonEmptyString(cached)) {
      return new Response(cached, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "x-calorisor-cache": "hit",
          ...limitHeaders(tier, photoUsed, textUsed),
        },
      });
    }

    // Cache miss → enforce the per-pool daily limit before the paid OpenAI call.
    const used = pool === "photo" ? photoUsed : textUsed;
    if (used >= DAILY_LIMITS[tier][pool]) {
      return dailyLimitResponse(pool, tier, photoUsed, textUsed);
    }
  } catch {
    return jsonError("upstream_error", 502);
  }

  let upstream: Response;
  try {
    upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: body.tier === "pro" ? "gpt-5-mini" : "gpt-5-nano",
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

  return new Response(content, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "x-calorisor-cache": "miss",
      ...limitHeaders(tier, photoUsed, textUsed),
    },
  });
}
