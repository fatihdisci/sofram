import { compactVerify, decodeProtectedHeader, decodeJwt, importX509 } from "jose";

export const PRO_PRODUCT_IDS = new Set([
  "com.fatih.calorisor.monthly",
  "com.fatih.calorisor.annual",
]);

export interface EntitlementDecision {
  tier: "free" | "pro";
  productID?: string;
  expiresAt?: number;
  verificationFailed: boolean;
  reason?: string;
}

interface AppleTransactionPayload {
  productId?: unknown;
  productID?: unknown;
  expiresDate?: unknown;
  expirationDate?: unknown;
  revocationDate?: unknown;
}

function asMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

export function evaluateTransactionPayload(
  payload: AppleTransactionPayload,
  now: number = Date.now(),
): EntitlementDecision {
  const productID = typeof payload.productId === "string"
    ? payload.productId
    : typeof payload.productID === "string" ? payload.productID : undefined;
  const expiresAt = asMillis(payload.expiresDate ?? payload.expirationDate);
  const revoked = payload.revocationDate !== undefined && payload.revocationDate !== null;

  if (!productID || !PRO_PRODUCT_IDS.has(productID)) {
    return { tier: "free", verificationFailed: true, reason: "unsupported_product" };
  }
  if (!expiresAt || expiresAt <= now) {
    return { tier: "free", productID, expiresAt, verificationFailed: false, reason: "expired" };
  }
  if (revoked) {
    return { tier: "free", productID, expiresAt, verificationFailed: false, reason: "revoked" };
  }
  return { tier: "pro", productID, expiresAt, verificationFailed: false };
}

function derToPem(base64: string): string {
  const lines = base64.match(/.{1,64}/g)?.join("\n") ?? base64;
  return `-----BEGIN CERTIFICATE-----\n${lines}\n-----END CERTIFICATE-----`;
}

/**
 * Verify Apple's compact JWS and its x5c chain. The root certificate digest is
 * supplied as APPLE_ROOT_CA_SHA256 so the deployment pins Apple's Root CA
 * without shipping a mutable network fetch into the edge function.
 */
export async function verifyAppleTransactionJWS(
  jws: string,
  now: number = Date.now(),
): Promise<EntitlementDecision> {
  try {
    const header = decodeProtectedHeader(jws);
    if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length < 2) {
      return { tier: "free", verificationFailed: true, reason: "invalid_certificate_chain" };
    }

    const rootDigest = process.env.APPLE_ROOT_CA_SHA256?.toLowerCase();
    if (!rootDigest) {
      return { tier: "free", verificationFailed: true, reason: "missing_root_pin" };
    }
    const rootBytes = Uint8Array.from(atob(header.x5c.at(-1)!), (char) => char.charCodeAt(0));
    const digest = await crypto.subtle.digest("SHA-256", rootBytes);
    const digestHex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
    if (digestHex !== rootDigest) {
      return { tier: "free", verificationFailed: true, reason: "untrusted_root" };
    }

    const leaf = await importX509(derToPem(header.x5c[0]!), "ES256");
    const verified = await compactVerify(jws, leaf);
    const payload = JSON.parse(new TextDecoder().decode(verified.payload)) as AppleTransactionPayload;
    return evaluateTransactionPayload(payload, now);
  } catch {
    return { tier: "free", verificationFailed: true, reason: "invalid_jws" };
  }
}

export async function resolveEntitlement(
  redis: { get<T = unknown>(key: string): Promise<T | null>; set(key: string, value: string, options: { ex: number }): Promise<unknown> },
  installationHash: string,
  signedTransactionInfo: string | undefined,
  claimedPro: boolean,
  now: number = Date.now(),
): Promise<EntitlementDecision> {
  const key = `calorisor:entitlement:${installationHash}`;
  const cached = await redis.get<string>(key);
  if (cached) {
    try {
      const decision = JSON.parse(cached) as EntitlementDecision;
      if (decision.expiresAt === undefined || decision.expiresAt > now) return decision;
    } catch { /* overwrite malformed cache */ }
  }

  if (!signedTransactionInfo) {
    return claimedPro
      ? { tier: "free", verificationFailed: true, reason: "missing_transaction" }
      : { tier: "free", verificationFailed: false };
  }

  const decision = await verifyAppleTransactionJWS(signedTransactionInfo, now);
  await redis.set(key, JSON.stringify(decision), { ex: 30 * 60 });
  return decision;
}
