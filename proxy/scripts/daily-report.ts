import { Redis } from "@upstash/redis";

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
  "tokens:output",
  "cost:microusd",
  "status:error",
  "rate_limited",
  "verification_failed",
] as const;

export type MetricName = (typeof METRIC_NAMES)[number];

export interface DailyReport {
  date: string;
  metrics: Record<MetricName, number>;
  cacheHitRate: number;
  freeShare: number;
  estimatedCostUsd: number;
  anomalies: Record<"installation_burst" | "invalid_key" | "verification_failure" | "daily_cost_threshold", number>;
  warnings: string[];
}

interface MetricsRedis {
  mget(...keys: string[]): Promise<unknown[]>;
}

const ANOMALY_NAMES = [
  "installation_burst",
  "invalid_key",
  "verification_failure",
  "daily_cost_threshold",
] as const;

function metricKey(date: string, name: MetricName): string {
  return `metrics:${date}:${name}`;
}

function asNumber(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export async function loadDailyReport(
  redis: MetricsRedis,
  date: string,
): Promise<DailyReport> {
  const keys = METRIC_NAMES.map((name) => metricKey(date, name));
  const anomalyKeys = ANOMALY_NAMES.map((name) => `metrics:${date}:anomaly:${name}`);
  const values = await redis.mget(...keys, ...anomalyKeys);
  const metrics = Object.fromEntries(
    METRIC_NAMES.map((name, index) => [name, asNumber(values[index])]),
  ) as Record<MetricName, number>;

  const cacheTotal = metrics["cache:hit"] + metrics["cache:miss"];
  const requestTotal = metrics["requests:total"];

  const anomalies = Object.fromEntries(
    ANOMALY_NAMES.map((name, index) => [name, asNumber(values[keys.length + index])]),
  ) as DailyReport["anomalies"];
  const warnings: string[] = [];
  const costThreshold = Number(process.env.CALORISOR_DAILY_COST_ALERT_MICROUSD ?? 10_000_000) / 1_000_000;
  if (reportCost(metrics) >= costThreshold) warnings.push(`UYARI: günlük tahmini maliyet eşiği aşıldı ($${reportCost(metrics).toFixed(6)}).`);
  if (anomalies.installation_burst > 0) warnings.push(`UYARI: installation burst sinyali (${anomalies.installation_burst}).`);
  if (anomalies.invalid_key > 0) warnings.push(`UYARI: geçersiz client key sinyali (${anomalies.invalid_key}).`);
  if (anomalies.verification_failure > 0) warnings.push(`UYARI: abonelik doğrulama hatası (${anomalies.verification_failure}).`);
  return {
    date,
    metrics,
    cacheHitRate: cacheTotal === 0 ? 0 : metrics["cache:hit"] / cacheTotal,
    freeShare: requestTotal === 0 ? 0 : metrics["requests:free"] / requestTotal,
    estimatedCostUsd: metrics["cost:microusd"] / 1_000_000,
    anomalies,
    warnings,
  };
}

function reportCost(metrics: Record<MetricName, number>): number {
  return metrics["cost:microusd"] / 1_000_000;
}

export function formatDailyReport(report: DailyReport): string {
  const { metrics } = report;
  return [
    `Calorisor proxy report — ${report.date}`,
    `Requests: ${metrics["requests:total"]} total | ${metrics["requests:free"]} free | ${metrics["requests:pro"]} pro`,
    `Modes: ${metrics["mode:photo"]} photo | ${metrics["mode:text"]} text | ${metrics["source:voice"]} voice`,
    `Cache: ${metrics["cache:hit"]} hit | ${metrics["cache:miss"]} miss | ${(report.cacheHitRate * 100).toFixed(1)}% hit rate`,
    `Tokens: ${metrics["tokens:input"]} input | ${metrics["tokens:output"]} output`,
    `Estimated cost: ${metrics["cost:microusd"]} microusd ($${report.estimatedCostUsd.toFixed(6)})`,
    `Errors: ${metrics["status:error"]} | rate limited: ${metrics.rate_limited}`,
    ...report.warnings,
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
