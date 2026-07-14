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
] as const;

export type MetricName = (typeof METRIC_NAMES)[number];

export interface DailyReport {
  date: string;
  metrics: Record<MetricName, number>;
  cacheHitRate: number;
  freeShare: number;
  estimatedCostUsd: number;
}

interface MetricsRedis {
  mget(...keys: string[]): Promise<unknown[]>;
}

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
  const values = await redis.mget(...keys);
  const metrics = Object.fromEntries(
    METRIC_NAMES.map((name, index) => [name, asNumber(values[index])]),
  ) as Record<MetricName, number>;

  const cacheTotal = metrics["cache:hit"] + metrics["cache:miss"];
  const requestTotal = metrics["requests:total"];

  return {
    date,
    metrics,
    cacheHitRate: cacheTotal === 0 ? 0 : metrics["cache:hit"] / cacheTotal,
    freeShare: requestTotal === 0 ? 0 : metrics["requests:free"] / requestTotal,
    estimatedCostUsd: metrics["cost:microusd"] / 1_000_000,
  };
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
