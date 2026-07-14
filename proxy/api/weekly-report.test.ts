import { webcrypto } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

const fakes = vi.hoisted(() => {
  const values = new Map<string, number | string>();
  const requestLogs: string[] = [];
  let entitlement = "pro";
  const redis = {
    get: vi.fn(async (key: string) => {
      if (key.startsWith("calorisor:entitlement:")) {
        return JSON.stringify({
          tier: entitlement,
          verificationFailed: false,
          expiresAt: Date.now() + 60_000,
        });
      }
      return values.get(key) ?? null;
    }),
    set: vi.fn(async (key: string, value: string) => {
      values.set(key, value);
      return "OK";
    }),
    incrby: vi.fn(async (key: string, amount: number) => {
      const next = Number(values.get(key) ?? 0) + amount;
      values.set(key, next);
      return next;
    }),
    expire: vi.fn(async () => 1),
    lpush: vi.fn(async (_key: string, value: string) => {
      requestLogs.unshift(value);
      return requestLogs.length;
    }),
    ltrim: vi.fn(async () => "OK"),
  };
  const fetch = vi.fn();

  return {
    redis,
    fetch,
    values,
    requestLogs,
    setEntitlement(value: "free" | "pro") {
      entitlement = value;
    },
    reset() {
      values.clear();
      entitlement = "pro";
      requestLogs.length = 0;
      redis.get.mockClear();
      redis.set.mockClear();
      redis.incrby.mockClear();
      redis.expire.mockClear();
      redis.lpush.mockClear();
      redis.ltrim.mockClear();
      fetch.mockReset();
    },
  };
});

vi.mock("@upstash/redis", () => ({
  Redis: { fromEnv: vi.fn(() => fakes.redis) },
}));

import handler from "./weekly-report.js";

const summary = {
  period_days: 7,
  registered_days: 5,
  average_calories: 1840,
  average_protein_g: 86,
  target_met_days: 4,
  highest_calorie_day: 2300,
  lowest_calorie_day: 1400,
  night_meal_count: 1,
  calorie_change_from_previous_week: -120,
  calorie_change_percent_from_previous_week: -6.1,
  active_energy_kcal: 3200,
  weight_change_kg: -0.4,
};

function request(body: Record<string, unknown>): Request {
  return new Request("https://proxy.test/api/weekly-report", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-calorisor-key": "test-client-key",
      "x-calorisor-installation-id": "installation-a",
    },
    body: JSON.stringify(body),
  });
}

function body(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    summary,
    week: "2026-W29",
    locale: "tr_TR",
    signed_transaction_info: "test-jws",
    schema_version: 1,
    app_version: "1.0",
    ...overrides,
  };
}

beforeEach(() => {
  process.env.CALORISOR_CLIENT_KEY = "test-client-key";
  process.env.OPENAI_API_KEY = "test-openai-key";
  process.env.INSTALLATION_HASH_SALT = "test-installation-salt";
  vi.stubGlobal("crypto", webcrypto);
  vi.stubGlobal("fetch", fakes.fetch);
  fakes.reset();
  fakes.fetch.mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
    const requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    expect(String(input)).toBe("https://api.openai.com/v1/chat/completions");
    expect(requestBody.model).toBe("gpt-5-mini");
    return new Response(JSON.stringify({
      choices: [{
        message: {
          content: JSON.stringify({
            headline: "Dengeli bir hafta",
            summary: "Haftanın genel görünümü istikrarlı.",
            observations: ["Beş gün kayıt var."],
            suggestions: ["Öğün kayıtlarını düzenli sürdürmeyi deneyebilirsin."],
          }),
        },
      }],
      usage: { prompt_tokens: 100, completion_tokens: 50 },
    }), { status: 200, headers: { "content-type": "application/json" } });
  });
});

describe("POST /api/weekly-report proxy contract", () => {
  it("sends only the derived summary, verifies Pro, and caches by week", async () => {
    const first = await handler(request(body()));
    const second = await handler(request(body()));

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.headers.get("x-calorisor-cache")).toBe("miss");
    expect(second.headers.get("x-calorisor-cache")).toBe("hit");
    expect(fakes.fetch).toHaveBeenCalledTimes(1);

    const openAIRequest = JSON.parse(String(fakes.fetch.mock.calls[0][1].body)) as {
      messages: Array<{ content: Array<{ text: string }> }>;
    };
    const prompt = openAIRequest.messages[0].content[0].text;
    expect(prompt).toContain('"registered_days":5');
    expect(prompt).toContain('"average_calories":1840');
    expect(prompt).not.toContain("raw_meal_history");
    expect(prompt).not.toContain("image_base64");
    expect(prompt).not.toContain("healthkit_samples");

    const log = fakes.requestLogs
      .map((entry) => JSON.parse(entry) as Record<string, unknown>)
      .find((entry) => entry.cache_status === "miss");
    expect(log).toBeDefined();
    const missLog = log!;
    expect(missLog).toHaveProperty("estimated_cost_microusd", 125);
    expect(missLog).toHaveProperty("summary_hash");
    expect(missLog).not.toHaveProperty("summary");
    expect(missLog).not.toHaveProperty("prompt");
  });

  it("allows an explicit refresh to replace the same week's cache", async () => {
    await handler(request(body()));
    const refreshed = await handler(request(body({ force_refresh: true })));

    expect(refreshed.status).toBe(200);
    expect(refreshed.headers.get("x-calorisor-cache")).toBe("miss");
    expect(fakes.fetch).toHaveBeenCalledTimes(2);
  });

  it("rejects raw or malformed summary input before OpenAI", async () => {
    const response = await handler(request(body({
      raw_meals: [{ name: "mercimek" }],
    })));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_request" });
    expect(fakes.fetch).not.toHaveBeenCalled();
  });

  it("does not let a non-Pro entitlement request a report", async () => {
    fakes.setEntitlement("free");

    const response = await handler(request(body()));

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "subscription_required" });
    expect(fakes.fetch).not.toHaveBeenCalled();
  });
});
