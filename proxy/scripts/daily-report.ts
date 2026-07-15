import { Redis } from "@upstash/redis";
import { MODEL_PRICING, type PricedModel } from "../lib/openai-cost.js";
import { dailyCostAlertMicrousd } from "../lib/metrics.js";

/** Scan request/token counters (written by api/scan.ts). */
const SCAN_METRIC_NAMES = [
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
type ScanMetricName = (typeof SCAN_METRIC_NAMES)[number];

/** Cost counters (written by recordOpenAICost — the single cost writer). */
const COST_NAMES = [
  "cost:microusd",
  "cost:scan",
  "cost:weekly",
  "cost:mode:photo",
  "cost:mode:text",
] as const;
type CostName = (typeof COST_NAMES)[number];

/** Weekly-report request/token counters (written by api/weekly-report.ts). */
const WEEKLY_METRIC_NAMES = [
  "weekly:requests",
  "weekly:cache:hit",
  "weekly:cache:miss",
  "weekly:tokens:input",
  "weekly:tokens:cached_input",
  "weekly:tokens:output",
  "weekly:tokens:reasoning",
  "weekly:status:error",
] as const;
type WeeklyMetricName = (typeof WEEKLY_METRIC_NAMES)[number];

const ANOMALY_NAMES = [
  "installation_burst",
  "invalid_key",
  "verification_failure",
  "daily_cost_threshold",
] as const;
type AnomalyName = (typeof ANOMALY_NAMES)[number];

const MODEL_NAMES = Object.keys(MODEL_PRICING) as PricedModel[];

export interface TokenTotals {
  /** Uncached (full-price) input tokens = input − cached input. */
  normalInput: number;
  cachedInput: number;
  output: number;
  reasoning: number;
}

export interface DailyReport {
  date: string;
  scan: Record<ScanMetricName, number>;
  weekly: Record<WeeklyMetricName, number>;
  cost: Record<CostName, number> & { model: Record<string, number> };
  tokens: { scan: TokenTotals; weekly: TokenTotals; openai: TokenTotals };
  averages: {
    perRequestMicrousd: number;
    perPhotoMicrousd: number;
    perTextMicrousd: number;
    perWeeklyReportMicrousd: number;
  };
  cacheHitRate: number;
  freeShare: number;
  anomalies: Record<AnomalyName, number>;
  warnings: string[];
}

interface MetricsRedis {
  mget(...keys: string[]): Promise<unknown[]>;
}

function metricKey(date: string, name: string): string {
  return `metrics:${date}:${name}`;
}

function asNumber(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** Safe integer division for average costs; 0 when there were no requests. */
function ratio(total: number, count: number): number {
  return count > 0 ? Math.round(total / count) : 0;
}

function tokenTotals(
  input: number,
  cachedInput: number,
  output: number,
  reasoning: number,
): TokenTotals {
  return {
    normalInput: Math.max(0, input - cachedInput),
    cachedInput,
    output,
    reasoning,
  };
}

export async function loadDailyReport(
  redis: MetricsRedis,
  date: string,
): Promise<DailyReport> {
  const scanKeys = SCAN_METRIC_NAMES.map((name) => metricKey(date, name));
  const costKeys = COST_NAMES.map((name) => metricKey(date, name));
  const modelCostKeys = MODEL_NAMES.map((model) => metricKey(date, `cost:model:${model}`));
  const weeklyKeys = WEEKLY_METRIC_NAMES.map((name) => metricKey(date, name));
  const anomalyKeys = ANOMALY_NAMES.map((name) => metricKey(date, `anomaly:${name}`));

  const values = await redis.mget(
    ...scanKeys,
    ...costKeys,
    ...modelCostKeys,
    ...weeklyKeys,
    ...anomalyKeys,
  );

  let offset = 0;
  const take = <T extends string>(names: readonly T[]): Record<T, number> => {
    const record = Object.fromEntries(
      names.map((name, index) => [name, asNumber(values[offset + index])]),
    ) as Record<T, number>;
    offset += names.length;
    return record;
  };

  const scan = take(SCAN_METRIC_NAMES);
  const cost = take(COST_NAMES);
  const modelCost = Object.fromEntries(
    MODEL_NAMES.map((model, index) => [model, asNumber(values[offset + index])]),
  ) as Record<string, number>;
  offset += MODEL_NAMES.length;
  const weekly = take(WEEKLY_METRIC_NAMES);
  const anomalies = Object.fromEntries(
    ANOMALY_NAMES.map((name, index) => [name, asNumber(values[offset + index])]),
  ) as Record<AnomalyName, number>;

  const scanTokens = tokenTotals(
    scan["tokens:input"],
    scan["tokens:cached_input"],
    scan["tokens:output"],
    scan["tokens:reasoning"],
  );
  const weeklyTokens = tokenTotals(
    weekly["weekly:tokens:input"],
    weekly["weekly:tokens:cached_input"],
    weekly["weekly:tokens:output"],
    weekly["weekly:tokens:reasoning"],
  );
  const openaiTokens = tokenTotals(
    scan["tokens:input"] + weekly["weekly:tokens:input"],
    scan["tokens:cached_input"] + weekly["weekly:tokens:cached_input"],
    scan["tokens:output"] + weekly["weekly:tokens:output"],
    scan["tokens:reasoning"] + weekly["weekly:tokens:reasoning"],
  );

  const cacheTotal = scan["cache:hit"] + scan["cache:miss"];
  const warnings: string[] = [];
  if (cost["cost:microusd"] >= dailyCostAlertMicrousd()) {
    warnings.push(`UYARI: günlük kümülatif maliyet eşiği aşıldı (${formatUsd(cost["cost:microusd"])}).`);
  }
  if (anomalies.daily_cost_threshold > 0) {
    warnings.push(`UYARI: günlük maliyet alarmı tetiklendi (${anomalies.daily_cost_threshold}).`);
  }
  if (anomalies.installation_burst > 0) warnings.push(`UYARI: installation burst sinyali (${anomalies.installation_burst}).`);
  if (anomalies.invalid_key > 0) warnings.push(`UYARI: geçersiz client key sinyali (${anomalies.invalid_key}).`);
  if (anomalies.verification_failure > 0) warnings.push(`UYARI: abonelik doğrulama hatası (${anomalies.verification_failure}).`);

  return {
    date,
    scan,
    weekly,
    cost: { ...cost, model: modelCost },
    tokens: { scan: scanTokens, weekly: weeklyTokens, openai: openaiTokens },
    averages: {
      perRequestMicrousd: ratio(cost["cost:scan"], scan["requests:total"]),
      perPhotoMicrousd: ratio(cost["cost:mode:photo"], scan["mode:photo"]),
      perTextMicrousd: ratio(cost["cost:mode:text"], scan["mode:text"]),
      perWeeklyReportMicrousd: ratio(cost["cost:weekly"], weekly["weekly:requests"]),
    },
    cacheHitRate: cacheTotal === 0 ? 0 : scan["cache:hit"] / cacheTotal,
    freeShare: scan["requests:total"] === 0 ? 0 : scan["requests:free"] / scan["requests:total"],
    anomalies,
    warnings,
  };
}

/** microusd → human-readable USD with 6 decimals. */
function formatUsd(microusd: number): string {
  return `$${(microusd / 1_000_000).toFixed(6)}`;
}

/** "1234 microusd ($0.001234)" */
function money(microusd: number): string {
  return `${microusd} microusd (${formatUsd(microusd)})`;
}

export function formatDailyReport(report: DailyReport): string {
  const { scan, weekly, cost, tokens, averages } = report;
  const modelLines = MODEL_NAMES.map(
    (model) => `  ${model}: ${money(cost.model[model] ?? 0)}`,
  );
  return [
    `Calorisor proxy report — ${report.date}`,
    "",
    "SCAN REQUESTS",
    `  Total: ${scan["requests:total"]} | free: ${scan["requests:free"]} | pro: ${scan["requests:pro"]}`,
    `  Photo: ${scan["mode:photo"]} | text: ${scan["mode:text"]} | voice: ${scan["source:voice"]}`,
    `  Redis cache: ${scan["cache:hit"]} hit | ${scan["cache:miss"]} miss | ${(report.cacheHitRate * 100).toFixed(1)}% hit rate`,
    `  Errors: ${scan["status:error"]} | rate limited: ${scan.rate_limited} | verification failed: ${scan.verification_failed}`,
    "",
    "OPENAI TOKENS (scan + weekly)",
    `  Normal input: ${tokens.openai.normalInput} | cached input: ${tokens.openai.cachedInput}`,
    `  Output: ${tokens.openai.output} | reasoning: ${tokens.openai.reasoning}`,
    `  (scan: ${tokens.scan.normalInput}/${tokens.scan.cachedInput}/${tokens.scan.output}/${tokens.scan.reasoning} · weekly: ${tokens.weekly.normalInput}/${tokens.weekly.cachedInput}/${tokens.weekly.output}/${tokens.weekly.reasoning} — normal/cached/output/reasoning)`,
    "",
    "COST",
    `  Total OpenAI: ${money(cost["cost:microusd"])}`,
    `  Scan: ${money(cost["cost:scan"])} | weekly report: ${money(cost["cost:weekly"])}`,
    "  By model:",
    ...modelLines,
    "",
    "AVERAGE COST",
    `  Per scan request: ${money(averages.perRequestMicrousd)}`,
    `  Per photo: ${money(averages.perPhotoMicrousd)} | per text: ${money(averages.perTextMicrousd)}`,
    `  Per weekly report: ${money(averages.perWeeklyReportMicrousd)}`,
    "",
    "WEEKLY REPORTS",
    `  Requests: ${weekly["weekly:requests"]} | cache: ${weekly["weekly:cache:hit"]} hit / ${weekly["weekly:cache:miss"]} miss | errors: ${weekly["weekly:status:error"]}`,
    ...(report.warnings.length > 0 ? ["", ...report.warnings] : []),
  ].join("\n");
}

function utcDate(): string {
  return new Date().toISOString().slice(0, 10);
}

async function main(): Promise<void> {
  const date = process.argv[2] ?? utcDate();
  const report = await loadDailyReport(Redis.fromEnv(), date);
  console.log(formatDailyReport(report));
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
