import { Redis } from "@upstash/redis";
import { resolveEntitlement } from "../lib/entitlement.js";
import { weeklyReportPrompt } from "../prompts.js";

export const config = {
  runtime: "edge",
};

type WeeklySummary = {
  period_days: number;
  registered_days: number;
  average_calories: number;
  average_protein_g: number;
  target_met_days: number;
  highest_calorie_day: number | null;
  lowest_calorie_day: number | null;
  night_meal_count: number;
  calorie_change_from_previous_week: number | null;
  calorie_change_percent_from_previous_week: number | null;
  active_energy_kcal: number | null;
  weight_change_kg: number | null;
};

interface WeeklyReportRequest {
  summary: WeeklySummary;
  week: string;
  locale: string;
  signed_transaction_info: string;
  schema_version: number;
  app_version: string;
  force_refresh?: boolean;
}

interface OpenAIResponse {
  choices?: Array<{
    message?: { content?: string | null };
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
}

interface WeeklyTelemetry {
  requestID: string;
  startedAt: number;
  cacheStatus: "hit" | "miss";
  openAIResponseTimeMs: number;
  usage?: OpenAIResponse["usage"];
  estimatedCostMicrousd: number;
}

const REPORT_LOG_KEY = "calorisor:weekly-request-logs";
const REPORT_RETENTION_SECONDS = 35 * 24 * 60 * 60;
const REPORT_LOG_RETENTION_SECONDS = 30 * 24 * 60 * 60;
const CACHE_TTL_SECONDS = 7 * 24 * 60 * 60;

const weeklyReportSchema = {
  name: "weekly_report",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      headline: { type: "string" },
      summary: { type: "string" },
      observations: {
        type: "array",
        items: { type: "string" },
        minItems: 0,
        maxItems: 3,
      },
      suggestions: {
        type: "array",
        items: { type: "string" },
        minItems: 1,
        maxItems: 2,
      },
    },
    required: ["headline", "summary", "observations", "suggestions"],
  },
} as const;

function jsonError(
  error: "invalid_request" | "unauthorized" | "subscription_required"
    | "subscription_verification_failed" | "upstream_error" | "service_unavailable",
  status: number,
): Response {
  return Response.json(
    { error },
    { status, headers: { "x-calorisor-cache": "miss" } },
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isFiniteNumberOrNull(value: unknown): value is number | null {
  return value === null || isFiniteNumber(value);
}

function hasOnlyKeys(value: object, keys: string[]): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function isWeeklySummary(value: unknown): value is WeeklySummary {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const summary = value as Record<string, unknown>;
  if (!hasOnlyKeys(summary, [
    "period_days",
    "registered_days",
    "average_calories",
    "average_protein_g",
    "target_met_days",
    "highest_calorie_day",
    "lowest_calorie_day",
    "night_meal_count",
    "calorie_change_from_previous_week",
    "calorie_change_percent_from_previous_week",
    "active_energy_kcal",
    "weight_change_kg",
  ])) return false;

  const integerInRange = (key: string, min: number, max: number) =>
    Number.isInteger(summary[key]) && Number(summary[key]) >= min && Number(summary[key]) <= max;
  const bounded = (key: string, min: number, max: number) =>
    isFiniteNumber(summary[key]) && Number(summary[key]) >= min && Number(summary[key]) <= max;

  return integerInRange("period_days", 1, 7)
    && integerInRange("registered_days", 0, 7)
    && bounded("average_calories", 0, 20_000)
    && bounded("average_protein_g", 0, 2_000)
    && integerInRange("target_met_days", 0, 7)
    && isFiniteNumberOrNull(summary.highest_calorie_day)
    && (summary.highest_calorie_day === null || (summary.highest_calorie_day >= 0 && summary.highest_calorie_day <= 20_000))
    && isFiniteNumberOrNull(summary.lowest_calorie_day)
    && (summary.lowest_calorie_day === null || (summary.lowest_calorie_day >= 0 && summary.lowest_calorie_day <= 20_000))
    && integerInRange("night_meal_count", 0, 100)
    && isFiniteNumberOrNull(summary.calorie_change_from_previous_week)
    && (summary.calorie_change_from_previous_week === null || Math.abs(summary.calorie_change_from_previous_week) <= 20_000)
    && isFiniteNumberOrNull(summary.calorie_change_percent_from_previous_week)
    && (summary.calorie_change_percent_from_previous_week === null || Math.abs(summary.calorie_change_percent_from_previous_week) <= 10_000)
    && isFiniteNumberOrNull(summary.active_energy_kcal)
    && (summary.active_energy_kcal === null || summary.active_energy_kcal >= 0 && summary.active_energy_kcal <= 100_000)
    && isFiniteNumberOrNull(summary.weight_change_kg)
    && (summary.weight_change_kg === null || Math.abs(summary.weight_change_kg) <= 100);
}

function isWeeklyReportRequest(value: unknown): value is WeeklyReportRequest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return hasOnlyKeys(body, [
    "summary",
    "week",
    "locale",
    "signed_transaction_info",
    "schema_version",
    "app_version",
    "force_refresh",
  ])
    && isWeeklySummary(body.summary)
    && typeof body.week === "string" && /^\d{4}-W\d{2}$/.test(body.week)
    && isNonEmptyString(body.locale) && body.locale.length <= 20
    && isNonEmptyString(body.signed_transaction_info) && body.signed_transaction_info.length <= 100_000
    && body.schema_version === 1
    && isNonEmptyString(body.app_version) && body.app_version.length <= 40
    && (body.force_refresh === undefined || typeof body.force_refresh === "boolean");
}

function nonNegativeInteger(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.floor(value))
    : 0;
}

function estimatedCostMicrousd(usage: OpenAIResponse["usage"] | undefined): number {
  if (!usage) return 0;
  return Math.round(
    (nonNegativeInteger(usage.prompt_tokens) * 250_000
      + nonNegativeInteger(usage.completion_tokens) * 2_000_000) / 1_000_000,
  );
}

function telemetryHeaders(telemetry: WeeklyTelemetry): Record<string, string> {
  return {
    "x-calorisor-request-id": telemetry.requestID,
    "x-calorisor-response-time-ms": String(Math.max(0, Date.now() - telemetry.startedAt)),
    "x-calorisor-openai-response-time-ms": String(telemetry.openAIResponseTimeMs),
    "x-calorisor-input-tokens": String(nonNegativeInteger(telemetry.usage?.prompt_tokens)),
    "x-calorisor-output-tokens": String(nonNegativeInteger(telemetry.usage?.completion_tokens)),
    "x-calorisor-estimated-cost-microusd": String(telemetry.estimatedCostMicrousd),
    "x-calorisor-cache": telemetry.cacheStatus,
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function utcDate(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function clientIP(request: Request): string {
  return request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || request.headers.get("x-real-ip")?.trim()
    || "unknown";
}

function isValidReportContent(content: string): boolean {
  try {
    const value = JSON.parse(content) as Record<string, unknown>;
    return typeof value.headline === "string"
      && typeof value.summary === "string"
      && Array.isArray(value.observations)
      && value.observations.length <= 3
      && value.observations.every((item) => typeof item === "string")
      && Array.isArray(value.suggestions)
      && value.suggestions.length >= 1
      && value.suggestions.length <= 2
      && value.suggestions.every((item) => typeof item === "string");
  } catch {
    return false;
  }
}

function summaryForHash(summary: WeeklySummary): string {
  return JSON.stringify({
    period_days: summary.period_days,
    registered_days: summary.registered_days,
    average_calories: summary.average_calories,
    average_protein_g: summary.average_protein_g,
    target_met_days: summary.target_met_days,
    highest_calorie_day: summary.highest_calorie_day,
    lowest_calorie_day: summary.lowest_calorie_day,
    night_meal_count: summary.night_meal_count,
    calorie_change_from_previous_week: summary.calorie_change_from_previous_week,
    calorie_change_percent_from_previous_week: summary.calorie_change_percent_from_previous_week,
    active_energy_kcal: summary.active_energy_kcal,
    weight_change_kg: summary.weight_change_kg,
  });
}

type ReportLogStatus = "success" | "error";

async function safeRecordReportMetrics(
  redis: Redis,
  telemetry: WeeklyTelemetry,
  week: string,
  summaryHash: string,
  status: ReportLogStatus,
  error?: string,
): Promise<void> {
  try {
    const date = utcDate();
    const prefix = `metrics:${date}:weekly`;
    const increments: Array<[string, number]> = [
      ["requests", 1],
      [`cache:${telemetry.cacheStatus}`, 1],
      ["tokens:input", nonNegativeInteger(telemetry.usage?.prompt_tokens)],
      ["tokens:output", nonNegativeInteger(telemetry.usage?.completion_tokens)],
      ["cost:microusd", telemetry.estimatedCostMicrousd],
    ];
    if (status === "error") increments.push(["status:error", 1]);

    await Promise.all([
      ...increments.map(([name, amount]) => redis.incrby(`${prefix}:${name}`, amount)),
      ...increments.map(([name]) => redis.expire(`${prefix}:${name}`, REPORT_RETENTION_SECONDS)),
      redis.lpush(REPORT_LOG_KEY, JSON.stringify({
        request_id: telemetry.requestID,
        timestamp: new Date().toISOString(),
        week,
        summary_hash: summaryHash,
        status,
        error: error ?? null,
        cache_status: telemetry.cacheStatus,
        response_time_ms: Math.max(0, Date.now() - telemetry.startedAt),
        openai_response_time_ms: telemetry.openAIResponseTimeMs,
        input_tokens: nonNegativeInteger(telemetry.usage?.prompt_tokens),
        output_tokens: nonNegativeInteger(telemetry.usage?.completion_tokens),
        estimated_cost_microusd: telemetry.estimatedCostMicrousd,
      })),
    ]);
    await Promise.all([
      redis.ltrim(REPORT_LOG_KEY, 0, 999),
      redis.expire(REPORT_LOG_KEY, REPORT_LOG_RETENTION_SECONDS),
    ]);
  } catch {
    // A metrics outage must not make a valid report unavailable.
  }
}

function weeklyResponse(content: string, telemetry: WeeklyTelemetry): Response {
  return new Response(content, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...telemetryHeaders(telemetry),
    },
  });
}

export default async function handler(request: Request): Promise<Response> {
  const telemetry: WeeklyTelemetry = {
    requestID: crypto.randomUUID(),
    startedAt: Date.now(),
    cacheStatus: "miss",
    openAIResponseTimeMs: 0,
    estimatedCostMicrousd: 0,
  };

  if (request.method !== "POST") return jsonError("invalid_request", 400);

  const clientKey = process.env.CALORISOR_CLIENT_KEY;
  if (!clientKey || request.headers.get("x-calorisor-key") !== clientKey) {
    return jsonError("unauthorized", 401);
  }

  const openAIKey = process.env.OPENAI_API_KEY;
  const installationSalt = process.env.INSTALLATION_HASH_SALT;
  if (!openAIKey || !installationSalt) return jsonError("service_unavailable", 503);

  let value: unknown;
  try {
    value = await request.json();
  } catch {
    return jsonError("invalid_request", 400);
  }
  if (!isWeeklyReportRequest(value)) return jsonError("invalid_request", 400);

  const body = value;
  const summaryJSON = summaryForHash(body.summary);
  const summaryHash = await sha256(summaryJSON);
  const cacheKey = `calorisor:weekly:${summaryHash}:${body.week}`;
  const installationID = request.headers.get("x-calorisor-installation-id")?.trim();
  const identitySource = isNonEmptyString(installationID) ? installationID : clientIP(request);
  const installationHash = await sha256(identitySource + installationSalt);

  let redis: Redis;
  try {
    redis = Redis.fromEnv();
    const entitlement = await resolveEntitlement(
      redis,
      installationHash,
      body.signed_transaction_info,
      false,
    );
    if (entitlement.tier !== "pro") {
      const error = entitlement.verificationFailed
        ? "subscription_verification_failed"
        : "subscription_required";
      await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "error", error);
      return jsonError(error, 403);
    }

    if (!body.force_refresh) {
      const cached = await redis.get<string>(cacheKey);
      if (isNonEmptyString(cached) && isValidReportContent(cached)) {
        telemetry.cacheStatus = "hit";
        await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "success");
        return weeklyResponse(cached, telemetry);
      }
    }
  } catch {
    return jsonError("upstream_error", 502);
  }

  const openAIStartedAt = Date.now();
  let upstream: Response;
  try {
    upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-5-mini",
        messages: [{
          role: "user",
          content: [{
            type: "text",
            text: weeklyReportPrompt(summaryJSON, body.locale),
          }],
        }],
        reasoning_effort: "minimal",
        response_format: {
          type: "json_schema",
          json_schema: weeklyReportSchema,
        },
        max_completion_tokens: 1200,
      }),
    });
  } catch {
    return jsonError("upstream_error", 502);
  }
  telemetry.openAIResponseTimeMs = Date.now() - openAIStartedAt;

  if (!upstream.ok) {
    await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "error", upstream.status === 429 ? "rate_limited" : "upstream_error");
    return jsonError("upstream_error", upstream.status === 429 ? 429 : 502);
  }

  let completion: OpenAIResponse;
  try {
    completion = await upstream.json() as OpenAIResponse;
  } catch {
    await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "error", "upstream_error");
    return jsonError("upstream_error", 502);
  }
  const content = completion.choices?.[0]?.message?.content;
  telemetry.usage = completion.usage;
  telemetry.estimatedCostMicrousd = estimatedCostMicrousd(completion.usage);
  if (!isNonEmptyString(content) || !isValidReportContent(content)) {
    await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "error", "invalid_response");
    return jsonError("upstream_error", 502);
  }

  try {
    await redis.set(cacheKey, content, { ex: CACHE_TTL_SECONDS });
  } catch {
    await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "error", "cache_write_failed");
    return jsonError("upstream_error", 502);
  }

  await safeRecordReportMetrics(redis, telemetry, body.week, summaryHash, "success");
  return weeklyResponse(content, telemetry);
}
