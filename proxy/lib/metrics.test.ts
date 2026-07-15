import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { recordOpenAICost } from "./metrics.js";

/** In-memory Redis fake that honors SET NX, so the once-per-day alarm guard is
 *  exercised for real (the endpoint test fakes do not implement NX). */
function makeRedis() {
  const values = new Map<string, string | number>();
  return {
    values,
    incrby: async (key: string, amount: number) => {
      const next = Number(values.get(key) ?? 0) + amount;
      values.set(key, next);
      return next;
    },
    expire: async () => 1,
    set: async (
      key: string,
      value: string,
      options: { nx?: true; ex: number },
    ) => {
      if (options.nx && values.has(key)) return null;
      values.set(key, value);
      return "OK";
    },
  };
}

const DATE = "2026-07-15";
const NEXT_DATE = "2026-07-16";

function anomalyCount(redis: ReturnType<typeof makeRedis>, date: string): number {
  return Number(redis.values.get(`metrics:${date}:anomaly:daily_cost_threshold`) ?? 0);
}

beforeEach(() => {
  process.env.CALORISOR_DAILY_COST_ALERT_MICROUSD = "1000";
});

afterEach(() => {
  delete process.env.CALORISOR_DAILY_COST_ALERT_MICROUSD;
});

describe("recordOpenAICost cumulative daily alarm", () => {
  it("aggregates the total plus per-dimension buckets", async () => {
    const redis = makeRedis();
    await recordOpenAICost(redis, {
      date: DATE,
      costMicrousd: 120,
      buckets: ["scan", "model:gpt-5-nano", "mode:photo"],
    });
    await recordOpenAICost(redis, {
      date: DATE,
      costMicrousd: 300,
      buckets: ["weekly", "model:gpt-5-mini"],
    });

    // The total daily counter sums scan + weekly.
    expect(redis.values.get(`metrics:${DATE}:cost:microusd`)).toBe(420);
    expect(redis.values.get(`metrics:${DATE}:cost:scan`)).toBe(120);
    expect(redis.values.get(`metrics:${DATE}:cost:weekly`)).toBe(300);
    expect(redis.values.get(`metrics:${DATE}:cost:model:gpt-5-nano`)).toBe(120);
    expect(redis.values.get(`metrics:${DATE}:cost:model:gpt-5-mini`)).toBe(300);
    expect(redis.values.get(`metrics:${DATE}:cost:mode:photo`)).toBe(120);
  });

  it("does not raise an anomaly below the threshold", async () => {
    const redis = makeRedis();
    const result = await recordOpenAICost(redis, {
      date: DATE,
      costMicrousd: 600,
      buckets: ["scan"],
    });

    expect(result.dailyTotalMicrousd).toBe(600);
    expect(result.thresholdTriggered).toBe(false);
    expect(anomalyCount(redis, DATE)).toBe(0);
  });

  it("raises exactly one anomaly when the cumulative total first crosses", async () => {
    const redis = makeRedis();
    // Neither request alone exceeds 1000, but together they do.
    const first = await recordOpenAICost(redis, { date: DATE, costMicrousd: 600, buckets: ["scan"] });
    const second = await recordOpenAICost(redis, { date: DATE, costMicrousd: 600, buckets: ["scan"] });

    expect(first.thresholdTriggered).toBe(false);
    expect(second.thresholdTriggered).toBe(true);
    expect(second.dailyTotalMicrousd).toBe(1_200);
    expect(anomalyCount(redis, DATE)).toBe(1);
  });

  it("does not re-alarm on later requests the same day", async () => {
    const redis = makeRedis();
    await recordOpenAICost(redis, { date: DATE, costMicrousd: 1_200, buckets: ["scan"] });
    const again = await recordOpenAICost(redis, { date: DATE, costMicrousd: 5_000, buckets: ["scan"] });

    expect(again.thresholdTriggered).toBe(false);
    expect(anomalyCount(redis, DATE)).toBe(1);
  });

  it("can alarm again on a new day", async () => {
    const redis = makeRedis();
    await recordOpenAICost(redis, { date: DATE, costMicrousd: 1_200, buckets: ["scan"] });
    expect(anomalyCount(redis, DATE)).toBe(1);

    const nextDay = await recordOpenAICost(redis, { date: NEXT_DATE, costMicrousd: 2_000, buckets: ["scan"] });
    expect(nextDay.thresholdTriggered).toBe(true);
    expect(anomalyCount(redis, NEXT_DATE)).toBe(1);
  });
});
