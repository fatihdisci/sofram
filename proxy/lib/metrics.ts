/**
 * Shared daily OpenAI cost aggregation and the cumulative daily-cost alarm.
 *
 * Every OpenAI-billed request — food scans (api/scan.ts) and Pro weekly reports
 * (api/weekly-report.ts) — funnels its cost through recordOpenAICost, which
 * keeps `metrics:{date}:cost:microusd` as the single source of truth for the
 * day's total spend and raises the daily-cost anomaly the FIRST time that
 * running total crosses the threshold. The alarm is deliberately about the
 * cumulative daily total, never a single request.
 */

/** Metric counters live ~35 days so the daily report can look a month back. */
export const METRIC_RETENTION_SECONDS = 35 * 24 * 60 * 60;

/** Fallback daily spend ceiling (microusd) — $10/day — when the env var is
 *  unset or invalid. */
const DEFAULT_DAILY_COST_ALERT_MICROUSD = 10_000_000;

/** Resolve the daily spend ceiling (microusd) from the environment. */
export function dailyCostAlertMicrousd(): number {
  // brand-keep: new CALP_* env wins; the old name is a transition fallback.
  const raw = Number(process.env.CALP_DAILY_COST_ALERT_MICROUSD ?? process.env.CALORISOR_DAILY_COST_ALERT_MICROUSD); // brand-keep
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_DAILY_COST_ALERT_MICROUSD;
}

/** Minimal Redis surface used here, so tests can supply a lightweight fake and
 *  we stay decoupled from the full @upstash/redis type (see lib/entitlement.ts
 *  for the same pattern). */
interface CostRedis {
  incrby(key: string, amount: number): Promise<number>;
  expire(key: string, seconds: number): Promise<unknown>;
  set(
    key: string,
    value: string,
    options: { nx: true; ex: number },
  ): Promise<unknown>;
}

export interface CostRecord {
  /** The day's cumulative OpenAI spend after this request was added. */
  dailyTotalMicrousd: number;
  /** True only on the single request that first crossed the threshold today. */
  thresholdTriggered: boolean;
}

function metricKey(date: string, name: string): string {
  return `metrics:${date}:${name}`;
}

/**
 * Add one request's cost (microusd) to the day's cumulative total and to each
 * per-dimension bucket (e.g. "scan", "weekly", "model:gpt-5-nano",
 * "mode:photo"), then raise the daily-cost anomaly exactly once per UTC day the
 * moment the running total first reaches the threshold.
 *
 * The anomaly is guarded by an NX flag so only the first request of the day to
 * cross the line counts an anomaly; every later request the same day stays
 * silent. Because all keys are date-scoped, a new UTC day starts fresh and can
 * alarm again. Callers wrap this so a metrics/Redis outage never fails a scan.
 */
export async function recordOpenAICost(
  redis: CostRedis,
  params: { date: string; costMicrousd: number; buckets: string[] },
): Promise<CostRecord> {
  const amount = Number.isFinite(params.costMicrousd)
    ? Math.max(0, Math.trunc(params.costMicrousd))
    : 0;
  const totalKey = metricKey(params.date, "cost:microusd");

  // Atomic running total, read back immediately so the threshold check below
  // sees this request already included.
  const dailyTotalMicrousd = await redis.incrby(totalKey, amount);
  await Promise.all([
    redis.expire(totalKey, METRIC_RETENTION_SECONDS),
    ...params.buckets.flatMap((bucket) => {
      const key = metricKey(params.date, `cost:${bucket}`);
      return [
        redis.incrby(key, amount),
        redis.expire(key, METRIC_RETENTION_SECONDS),
      ];
    }),
  ]);

  let thresholdTriggered = false;
  if (dailyTotalMicrousd >= dailyCostAlertMicrousd()) {
    // SET NX succeeds (returns truthy) only for the first crosser of the day;
    // subsequent same-day requests get null and skip the anomaly increment.
    const firstTrigger = await redis.set(
      metricKey(params.date, "anomaly:daily_cost_threshold_triggered"),
      "1",
      { nx: true, ex: METRIC_RETENTION_SECONDS },
    );
    if (firstTrigger) {
      thresholdTriggered = true;
      const anomalyKey = metricKey(params.date, "anomaly:daily_cost_threshold");
      await redis.incrby(anomalyKey, 1);
      await redis.expire(anomalyKey, METRIC_RETENTION_SECONDS);
    }
  }

  return { dailyTotalMicrousd, thresholdTriggered };
}
