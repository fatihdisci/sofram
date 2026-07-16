import { beforeAll, describe, expect, it } from "vitest";
import {
  evaluateTransactionPayload,
  loadAppleVerifierConfig,
  verifyAppleTransactionJWS,
} from "./entitlement.js";
import { createAppleTestChain, transactionPayload } from "./apple-test-chain.js";

const now = Date.parse("2026-07-16T00:00:00Z");

let chain: ReturnType<typeof createAppleTestChain>;
let sandboxEnv: Record<string, string | undefined>;
let productionEnv: Record<string, string | undefined>;

beforeAll(() => {
  chain = createAppleTestChain();
  // Sandbox never needs the numeric app id.
  sandboxEnv = {
    APPLE_ROOT_CERTIFICATES: chain.rootCertificateBase64,
    APPLE_BUNDLE_ID: "com.fatih.calp",
    APPLE_STOREKIT_ENVIRONMENT: "Sandbox",
  };
  // Production verification requires APPLE_APP_APPLE_ID.
  productionEnv = {
    APPLE_ROOT_CERTIFICATES: chain.rootCertificateBase64,
    APPLE_BUNDLE_ID: "com.fatih.calp",
    APPLE_STOREKIT_ENVIRONMENT: "Production",
    APPLE_APP_APPLE_ID: "6790000000",
  };
});

function sign(overrides: Record<string, unknown> = {}): string {
  return chain.signTransaction(transactionPayload({ signedDate: now, ...overrides }));
}

describe("Calp Pro entitlement policy (evaluateTransactionPayload)", () => {
  it("accepts an active monthly product", () => {
    const decision = evaluateTransactionPayload(
      { productId: "com.fatih.calp.monthly", expiresDate: now + 60_000 },
      now,
    );
    expect(decision).toMatchObject({ tier: "pro", verificationFailed: false });
  });

  it("accepts an active annual product", () => {
    const decision = evaluateTransactionPayload(
      { productId: "com.fatih.calp.annual", expiresDate: now + 60_000 },
      now,
    );
    expect(decision.tier).toBe("pro");
  });

  it("keeps legacy pre-rename products entitled after the Calp rename", () => {
    // brand-keep: pre-rename product IDs are immutable in App Store Connect.
    for (const productId of ["com.fatih.calorisor.monthly", "com.fatih.calorisor.annual"]) { // brand-keep
      expect(evaluateTransactionPayload({ productId, expiresDate: now + 60_000 }, now).tier).toBe("pro");
    }
  });

  it("maps an expired transaction to free without flagging verification", () => {
    const decision = evaluateTransactionPayload(
      { productId: "com.fatih.calp.monthly", expiresDate: now - 1 },
      now,
    );
    expect(decision).toMatchObject({ tier: "free", verificationFailed: false, reason: "expired" });
  });

  it("maps a revoked transaction to free", () => {
    const decision = evaluateTransactionPayload(
      { productId: "com.fatih.calp.monthly", expiresDate: now + 60_000, revocationDate: now - 1 },
      now,
    );
    expect(decision).toMatchObject({ tier: "free", verificationFailed: false, reason: "revoked" });
  });

  it("rejects an unsupported product as a verification failure", () => {
    const decision = evaluateTransactionPayload(
      { productId: "com.example.other", expiresDate: now + 60_000 },
      now,
    );
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "unsupported_product" });
  });
});

describe("StoreKit JWS verification (verifyAppleTransactionJWS)", () => {
  it("returns pro for a valid active monthly Sandbox transaction", async () => {
    const jws = sign({ productId: "com.fatih.calp.monthly" });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "pro", productID: "com.fatih.calp.monthly", verificationFailed: false });
  });

  it("returns pro for a valid active annual Sandbox transaction", async () => {
    const jws = sign({ productId: "com.fatih.calp.annual" });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "pro", productID: "com.fatih.calp.annual" });
  });

  it("verifies a real Production transaction using APPLE_APP_APPLE_ID", async () => {
    const jws = sign({ environment: "Production", productId: "com.fatih.calp.annual" });
    const decision = await verifyAppleTransactionJWS(jws, now, productionEnv);
    expect(decision.tier).toBe("pro");
  });

  it("falls back from Production to Sandbox when both are accepted", async () => {
    const bothEnv = { ...productionEnv, APPLE_STOREKIT_ENVIRONMENT: "Production,Sandbox" };
    const jws = sign({ environment: "Sandbox" });
    const decision = await verifyAppleTransactionJWS(jws, now, bothEnv);
    expect(decision.tier).toBe("pro");
  });

  it("keeps a legacy pre-rename product entitled through full verification", async () => {
    const jws = sign({ productId: "com.fatih.calorisor.annual" }); // brand-keep
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision.tier).toBe("pro");
  });

  it("maps an expired but validly-signed transaction to free", async () => {
    const jws = sign({ expiresDate: now - 60_000 });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: false, reason: "expired" });
  });

  it("maps a revoked transaction to free", async () => {
    const jws = sign({ revocationDate: now - 1, expiresDate: now + 60_000 });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: false, reason: "revoked" });
  });

  it("rejects an unsupported product even when the signature is valid", async () => {
    const jws = sign({ productId: "com.someone.else.pro" });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "unsupported_product" });
  });

  it("rejects a transaction signed for a different bundle id", async () => {
    const jws = sign({ bundleId: "com.attacker.app" });
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "wrong_bundle_id" });
  });

  it("rejects a Sandbox transaction when only Production is accepted", async () => {
    const jws = sign({ environment: "Sandbox" });
    const decision = await verifyAppleTransactionJWS(jws, now, productionEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "wrong_environment" });
  });

  it("rejects a malformed JWS", async () => {
    const decision = await verifyAppleTransactionJWS("not-a-valid-jws", now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "invalid_jws" });
  });

  it("rejects a JWS whose signature does not match the embedded certificate", async () => {
    const jws = chain.signWithForeignKey(transactionPayload({ signedDate: now }));
    const decision = await verifyAppleTransactionJWS(jws, now, sandboxEnv);
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "invalid_jws" });
  });

  it("fails closed when no root certificate is configured", async () => {
    const jws = sign();
    const decision = await verifyAppleTransactionJWS(jws, now, {
      APPLE_BUNDLE_ID: "com.fatih.calp",
      APPLE_STOREKIT_ENVIRONMENT: "Sandbox",
    });
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "missing_certificate_configuration" });
  });

  it("fails closed when Production is requested without APPLE_APP_APPLE_ID", async () => {
    const jws = sign({ environment: "Production" });
    const decision = await verifyAppleTransactionJWS(jws, now, {
      APPLE_ROOT_CERTIFICATES: chain.rootCertificateBase64,
      APPLE_BUNDLE_ID: "com.fatih.calp",
      APPLE_STOREKIT_ENVIRONMENT: "Production",
    });
    expect(decision).toMatchObject({ tier: "free", verificationFailed: true, reason: "missing_app_apple_id" });
  });
});

describe("loadAppleVerifierConfig", () => {
  it("defaults the bundle id and accepts both environments when unset", () => {
    const result = loadAppleVerifierConfig({
      APPLE_ROOT_CERTIFICATES: chain.rootCertificateBase64,
      APPLE_APP_APPLE_ID: "6790000000",
    });
    expect("config" in result).toBe(true);
    if ("config" in result) {
      expect(result.config.bundleId).toBe("com.fatih.calp");
      expect(result.config.environments).toHaveLength(2);
    }
  });

  it("reports missing certificate configuration", () => {
    expect(loadAppleVerifierConfig({})).toEqual({ error: "missing_certificate_configuration" });
  });

  it("rejects a non-numeric APPLE_APP_APPLE_ID", () => {
    const result = loadAppleVerifierConfig({
      APPLE_ROOT_CERTIFICATES: chain.rootCertificateBase64,
      APPLE_APP_APPLE_ID: "not-a-number",
    });
    expect(result).toEqual({ error: "invalid_app_apple_id" });
  });
});
