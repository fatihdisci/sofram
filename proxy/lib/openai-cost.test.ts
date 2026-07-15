import { describe, expect, it } from "vitest";
import {
  calculatedCostMicrousd,
  tokenBreakdown,
  type OpenAIUsage,
} from "./openai-cost.js";

describe("calculatedCostMicrousd", () => {
  it("prices nano input + output with no cache", () => {
    // 1000 × $0.05/1M = 50 ; 300 × $0.40/1M = 120 → 170 microusd.
    expect(
      calculatedCostMicrousd("gpt-5-nano", {
        prompt_tokens: 1_000,
        completion_tokens: 300,
      }),
    ).toBe(170);
  });

  it("prices mini input + output with no cache", () => {
    // 1000 × $0.25/1M = 250 ; 300 × $2.00/1M = 600 → 850 microusd.
    expect(
      calculatedCostMicrousd("gpt-5-mini", {
        prompt_tokens: 1_000,
        completion_tokens: 300,
      }),
    ).toBe(850);
  });

  it("bills cached input at the cheaper rate for nano (partial cache)", () => {
    // 500 uncached × $0.05 = 25 ; 1500 cached × $0.005 = 7.5 ;
    // 400 output × $0.40 = 160 → 192.5 → round → 193 microusd.
    expect(
      calculatedCostMicrousd("gpt-5-nano", {
        prompt_tokens: 2_000,
        completion_tokens: 400,
        prompt_tokens_details: { cached_tokens: 1_500 },
      }),
    ).toBe(193);
  });

  it("bills cached input at the cheaper rate for mini (partial cache)", () => {
    // 500 uncached × $0.25 = 125 ; 1500 cached × $0.025 = 37.5 ;
    // 400 output × $2.00 = 800 → 962.5 → round → 963 microusd.
    // (The formula gives 963, not 938 — half-up rounding of 962.5.)
    expect(
      calculatedCostMicrousd("gpt-5-mini", {
        prompt_tokens: 2_000,
        completion_tokens: 400,
        prompt_tokens_details: { cached_tokens: 1_500 },
      }),
    ).toBe(963);
  });

  it("clamps cached_tokens that exceed prompt_tokens", () => {
    // cached is capped at prompt_tokens (1000), uncached becomes 0:
    // 1000 cached × $0.005 = 5 microusd; no output.
    expect(
      calculatedCostMicrousd("gpt-5-nano", {
        prompt_tokens: 1_000,
        completion_tokens: 0,
        prompt_tokens_details: { cached_tokens: 5_000 },
      }),
    ).toBe(5);
  });

  it("treats negative token counts as zero", () => {
    expect(
      calculatedCostMicrousd("gpt-5-nano", {
        prompt_tokens: -100,
        completion_tokens: -50,
        prompt_tokens_details: { cached_tokens: -10 },
      }),
    ).toBe(0);
  });

  it("returns 0 for undefined usage", () => {
    expect(calculatedCostMicrousd("gpt-5-nano", undefined)).toBe(0);
  });

  it("returns 0 for an unknown model", () => {
    expect(
      calculatedCostMicrousd("gpt-4-turbo", {
        prompt_tokens: 1_000,
        completion_tokens: 300,
      }),
    ).toBe(0);
  });

  it("does not bill reasoning tokens a second time", () => {
    // Reasoning tokens live inside completion_tokens; adding the detail must not
    // change the cost versus the same completion_tokens without the detail.
    const withoutReasoning = calculatedCostMicrousd("gpt-5-nano", {
      prompt_tokens: 1_000,
      completion_tokens: 300,
    });
    const withReasoning = calculatedCostMicrousd("gpt-5-nano", {
      prompt_tokens: 1_000,
      completion_tokens: 300,
      completion_tokens_details: { reasoning_tokens: 200 },
    });
    expect(withReasoning).toBe(withoutReasoning);
    expect(withReasoning).toBe(170);
  });
});

describe("tokenBreakdown", () => {
  it("splits cached and uncached input and surfaces reasoning", () => {
    const usage: OpenAIUsage = {
      prompt_tokens: 2_000,
      completion_tokens: 400,
      prompt_tokens_details: { cached_tokens: 1_500 },
      completion_tokens_details: { reasoning_tokens: 120 },
    };
    expect(tokenBreakdown(usage)).toEqual({
      promptTokens: 2_000,
      completionTokens: 400,
      cachedInputTokens: 1_500,
      uncachedInputTokens: 500,
      reasoningTokens: 120,
    });
  });

  it("is all-zero for undefined usage", () => {
    expect(tokenBreakdown(undefined)).toEqual({
      promptTokens: 0,
      completionTokens: 0,
      cachedInputTokens: 0,
      uncachedInputTokens: 0,
      reasoningTokens: 0,
    });
  });
});
