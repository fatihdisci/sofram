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
  minuteLimit: Ratelimit;
  dailyLimit: Ratelimit;
}

const CACHE_TTL_SECONDS = 7 * 24 * 60 * 60;
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
    dailyLimit: new Ratelimit({
      redis,
      limiter: Ratelimit.slidingWindow(200, "1 d"),
      prefix: "calorisor:rate:day",
    }),
  };
  return upstashInfrastructure;
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

  let infrastructure: UpstashInfrastructure;
  let responseCacheKey: string;
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
    const [minute, daily] = await Promise.all([
      infrastructure.minuteLimit.limit(identity.key),
      infrastructure.dailyLimit.limit(identity.key),
    ]);
    if (!minute.success || !daily.success) {
      return jsonError("rate_limited", 429);
    }

    responseCacheKey = await cacheKey(body);
    const cached = await infrastructure.redis.get<string>(responseCacheKey);
    if (isNonEmptyString(cached)) {
      return new Response(cached, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "x-calorisor-cache": "hit",
        },
      });
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

  return new Response(content, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "x-calorisor-cache": "miss",
    },
  });
}
