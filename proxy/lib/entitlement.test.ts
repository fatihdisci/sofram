import { describe, expect, it } from "vitest";
import { evaluateTransactionPayload } from "./entitlement.js";

const future = Date.parse("2030-01-01T00:00:00Z");

describe("StoreKit entitlement payload policy", () => {
  it("accepts active monthly and annual products", () => {
    for (const productId of ["com.fatih.calp.monthly", "com.fatih.calp.annual"]) {
      expect(evaluateTransactionPayload({ productId, expiresDate: future + 60_000 }, future).tier).toBe("pro");
    }
  });

  it("keeps legacy pre-rename products entitled after the Calp rename", () => {
    // brand-keep: pre-rename product IDs are immutable in App Store Connect, so
    // anyone who subscribed before the rename must stay Pro under the same IDs.
    for (const productId of ["com.fatih.calorisor.monthly", "com.fatih.calorisor.annual"]) { // brand-keep
      expect(evaluateTransactionPayload({ productId, expiresDate: future + 60_000 }, future).tier).toBe("pro");
    }
  });

  it("maps expired and revoked transactions to free", () => {
    expect(evaluateTransactionPayload({ productId: "com.fatih.calp.monthly", expiresDate: future }, future).tier).toBe("free");
    expect(evaluateTransactionPayload({ productId: "com.fatih.calp.monthly", expiresDate: future + 60_000, revocationDate: future - 1 }, future).tier).toBe("free");
  });

  it("rejects unsupported products", () => {
    const decision = evaluateTransactionPayload({ productId: "com.example.other", expiresDate: future + 60_000 }, future);
    expect(decision.tier).toBe("free");
    expect(decision.verificationFailed).toBe(true);
  });
});
