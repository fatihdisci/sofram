import { webcrypto } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

const fakes = vi.hoisted(() => {
  const values = new Map<string, number | string>();
  const minuteLimit = {
    limit: vi.fn(async () => ({ success: true })),
  };

  const redis = {
    mget: vi.fn(async (...keys: string[]) =>
      keys.map((key) => values.get(key) ?? null),
    ),
    get: vi.fn(async (key: string) => values.get(key) ?? null),
    set: vi.fn(async (key: string, value: string) => {
      values.set(key, value);
      return "OK";
    }),
    incr: vi.fn(async (key: string) => {
      const next = Number(values.get(key) ?? 0) + 1;
      values.set(key, next);
      return next;
    }),
    expire: vi.fn(async () => 1),
  };

  const fetch = vi.fn();
  let incrementCount = 0;

  return {
    redis,
    minuteLimit,
    fetch,
    values,
    get incrementCount() {
      return incrementCount;
    },
    reset() {
      values.clear();
      incrementCount = 0;
      redis.mget.mockClear();
      redis.get.mockClear();
      redis.set.mockClear();
      redis.incr.mockImplementation(async (key: string) => {
        incrementCount += 1;
        const next = Number(values.get(key) ?? 0) + 1;
        values.set(key, next);
        return next;
      });
      redis.expire.mockClear();
      minuteLimit.limit.mockClear();
      fetch.mockReset();
    },
  };
});

vi.mock("@upstash/redis", () => ({
  Redis: { fromEnv: vi.fn(() => fakes.redis) },
}));

vi.mock("@upstash/ratelimit", () => {
  const Ratelimit = vi.fn(function () {
    return fakes.minuteLimit;
  });
  Ratelimit.slidingWindow = vi.fn(() => ({}));
  return { Ratelimit };
});

import handler from "./scan.js";

const successfulVisionResponse = JSON.stringify({
  items: [],
  no_food_detected: true,
});

function request(
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
): Request {
  return new Request("https://proxy.test/api/scan", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-calorisor-key": "test-client-key",
      "x-calorisor-installation-id": "installation-a",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function textBody(
  text: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    text,
    mode: "text",
    locale: "tr_TR",
    tier: "free",
    schema_version: 1,
    app_version: "1.0",
    ...overrides,
  };
}

function photoBody(
  image_base64: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    image_base64,
    mode: "photo",
    locale: "tr_TR",
    tier: "free",
    schema_version: 1,
    app_version: "1.0",
    ...overrides,
  };
}

beforeEach(() => {
  process.env.CALORISOR_CLIENT_KEY = "test-client-key";
  process.env.OPENAI_API_KEY = "test-openai-key";
  process.env.INSTALLATION_HASH_SALT = "test-installation-salt";
  delete process.env.REQUIRE_INSTALLATION_ID;
  vi.stubGlobal("crypto", webcrypto);
  vi.stubGlobal("fetch", fakes.fetch);
  fakes.reset();
  fakes.fetch.mockImplementation(async () =>
    new Response(
      JSON.stringify({
        choices: [{ message: { content: successfulVisionResponse } }],
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );
});

describe("POST /api/scan proxy contract", () => {
  it("separates cache entries by model and locale", async () => {
    const freeResponse = await handler(request(textBody("mercimek çorbası")));
    const proResponse = await handler(
      request(textBody("mercimek çorbası", { tier: "pro" })),
    );
    const englishResponse = await handler(
      request(
        textBody("mercimek çorbası", { tier: "pro", locale: "en_US" }),
      ),
    );
    const cachedEnglishResponse = await handler(
      request(
        textBody("mercimek çorbası", { tier: "pro", locale: "en_US" }),
      ),
    );

    expect(freeResponse.status).toBe(200);
    expect(proResponse.status).toBe(200);
    expect(englishResponse.status).toBe(200);
    expect(cachedEnglishResponse.status).toBe(200);
    expect(fakes.fetch).toHaveBeenCalledTimes(3);
    expect(cachedEnglishResponse.headers.get("x-calorisor-cache")).toBe("hit");
    expect(
      [...fakes.values.keys()].filter((key) => key.startsWith("calorisor:scan:v3:")),
    ).toHaveLength(3);
  });

  it("does not consume a daily quota on a cache hit", async () => {
    const first = await handler(request(textBody("yoğurt")));
    const second = await handler(request(textBody("yoğurt")));

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(second.headers.get("x-calorisor-cache")).toBe("hit");
    expect(second.headers.get("x-calorisor-text-remaining")).toBe("1");
    expect(second.headers.get("x-calorisor-input-tokens")).toBe("0");
    expect(second.headers.get("x-calorisor-output-tokens")).toBe("0");
    expect(second.headers.get("x-calorisor-estimated-cost-microusd")).toBe("0");
    expect(second.headers.get("x-calorisor-request-id")).toMatch(/^[0-9a-f-]{36}$/);
    expect(fakes.incrementCount).toBe(1);
    expect(fakes.fetch).toHaveBeenCalledTimes(1);
  });

  it("parses usage and calculates integer nano cost without requiring usage", async () => {
    fakes.fetch.mockImplementationOnce(async () =>
      new Response(
        JSON.stringify({
          choices: [{ message: { content: successfulVisionResponse } }],
          usage: { prompt_tokens: 1_000, completion_tokens: 500, total_tokens: 1_500 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );

    const response = await handler(request(textBody("elma")));
    expect(response.status).toBe(200);
    expect(response.headers.get("x-calorisor-input-tokens")).toBe("1000");
    expect(response.headers.get("x-calorisor-output-tokens")).toBe("500");
    // 1,000 × $0.05/M + 500 × $0.40/M = 250 microusd.
    expect(response.headers.get("x-calorisor-estimated-cost-microusd")).toBe("250");
    expect(response.headers.get("x-calorisor-openai-response-time-ms")).toMatch(/^\d+$/);
    expect(response.headers.get("x-calorisor-redis-lookup-time-ms")).toMatch(/^\d+$/);

    fakes.fetch.mockImplementationOnce(async () =>
      new Response(
        JSON.stringify({ choices: [{ message: { content: successfulVisionResponse } }] }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    const withoutUsage = await handler(request(textBody("armut")));
    expect(withoutUsage.status).toBe(200);
    expect(withoutUsage.headers.get("x-calorisor-estimated-cost-microusd")).toBe("0");
  });

  it("enforces the free text quota while allowing the photo pool separately", async () => {
    expect((await handler(request(textBody("elma")))).status).toBe(200);
    expect((await handler(request(textBody("armut")))).status).toBe(200);

    const thirdText = await handler(request(textBody("muz")));
    expect(thirdText.status).toBe(429);
    expect((await thirdText.json()).error).toBe("daily_limit_reached");

    const firstPhoto = await handler(request(photoBody("aGVsbG8x")));
    const secondPhoto = await handler(request(photoBody("aGVsbG8y")));
    expect(firstPhoto.status).toBe(200);
    expect(secondPhoto.status).toBe(429);
    expect((await secondPhoto.json()).limit_type).toBe("photo");
    expect(fakes.fetch).toHaveBeenCalledTimes(3);
  });

  it("rejects an invalid client key before touching infrastructure", async () => {
    const response = await handler(
      request(textBody("elma"), { "x-calorisor-key": "wrong-key" }),
    );

    expect(response.status).toBe(401);
    expect(fakes.redis.mget).not.toHaveBeenCalled();
    expect(fakes.fetch).not.toHaveBeenCalled();
  });
});
