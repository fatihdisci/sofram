import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";

export const PRO_PRODUCT_IDS = new Set([
  "com.fatih.calp.monthly",
  "com.fatih.calp.annual",
  // brand-keep: legacy pre-rename product IDs stay entitled for anyone who
  // subscribed before the Calp rename. App Store Connect product IDs are
  // immutable once created, so old subscriptions keep their original IDs.
  "com.fatih.calorisor.monthly", // brand-keep
  "com.fatih.calorisor.annual", // brand-keep
]);

export interface EntitlementDecision {
  tier: "free" | "pro";
  productID?: string;
  expiresAt?: number;
  verificationFailed: boolean;
  reason?: string;
}

/**
 * Environment variable names, defined centrally so the deployment docs, the
 * .env.example, and the runtime read the exact same keys. Everything Apple's
 * `SignedDataVerifier` needs to check a StoreKit `signedTransactionInfo` JWS is
 * sourced from these.
 */
export const APPLE_ENV = {
  /** The app's bundle identifier the transaction must be signed for. */
  bundleId: "APPLE_BUNDLE_ID",
  /** Numeric App Store app id (adamId). Required to verify Production data. */
  appAppleId: "APPLE_APP_APPLE_ID",
  /** Comma/newline separated base64 DER-encoded Apple root certificates. */
  rootCertificates: "APPLE_ROOT_CERTIFICATES",
  /** Comma separated environments to accept: `Sandbox`, `Production`. */
  environment: "APPLE_STOREKIT_ENVIRONMENT",
  /** Optional `true`/`false`; enables OCSP revocation + live expiry checks. */
  onlineChecks: "APPLE_ENABLE_ONLINE_CHECKS",
} as const;

/** Bundle id the app currently ships with (see fatihtodos.md §Mevcut durum). */
const DEFAULT_BUNDLE_ID = "com.fatih.calp";

/**
 * When APPLE_STOREKIT_ENVIRONMENT is unset we accept both, trying Production
 * first and falling back to Sandbox. This keeps TestFlight/dev builds (which
 * always sign Sandbox transactions) working alongside App Store production
 * users without redeploying with a different value.
 */
const DEFAULT_ENVIRONMENTS: Environment[] = [Environment.PRODUCTION, Environment.SANDBOX];

type EnvSource = Record<string, string | undefined>;

interface AppleVerifierConfig {
  bundleId: string;
  appAppleId?: number;
  rootCertificates: Buffer[];
  environments: Environment[];
  enableOnlineChecks: boolean;
}

type ConfigResult = { config: AppleVerifierConfig } | { error: string };

function parseEnvironments(raw: string | undefined): Environment[] {
  if (raw === undefined || raw.trim() === "") return DEFAULT_ENVIRONMENTS;
  const known = new Map<string, Environment>([
    ["sandbox", Environment.SANDBOX],
    ["production", Environment.PRODUCTION],
  ]);
  const parsed: Environment[] = [];
  for (const token of raw.split(/[,\s]+/)) {
    const environment = known.get(token.trim().toLowerCase());
    if (environment && !parsed.includes(environment)) parsed.push(environment);
  }
  return parsed;
}

function parseRootCertificates(raw: string | undefined): Buffer[] {
  if (raw === undefined || raw.trim() === "") return [];
  const certificates: Buffer[] = [];
  for (const token of raw.split(/[,\s]+/)) {
    const trimmed = token.trim();
    if (trimmed === "") continue;
    try {
      certificates.push(Buffer.from(trimmed, "base64"));
    } catch {
      // Skip an unparseable entry rather than poisoning the whole trust store.
    }
  }
  return certificates;
}

/**
 * Read and validate every Apple verification setting from the environment.
 * Returns a typed error string (not a throw) for any missing/invalid config so
 * the caller can fail closed to `free` with a diagnosable reason.
 */
export function loadAppleVerifierConfig(env: EnvSource = process.env): ConfigResult {
  const rootCertificates = parseRootCertificates(env[APPLE_ENV.rootCertificates]);
  if (rootCertificates.length === 0) {
    return { error: "missing_certificate_configuration" };
  }

  const environments = parseEnvironments(env[APPLE_ENV.environment]);
  if (environments.length === 0) {
    return { error: "invalid_environment_configuration" };
  }

  const bundleId = env[APPLE_ENV.bundleId]?.trim() || DEFAULT_BUNDLE_ID;

  let appAppleId: number | undefined;
  const rawAppAppleId = env[APPLE_ENV.appAppleId]?.trim();
  if (rawAppAppleId !== undefined && rawAppAppleId !== "") {
    const parsed = Number(rawAppAppleId);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      return { error: "invalid_app_apple_id" };
    }
    appAppleId = parsed;
  }

  const enableOnlineChecks = env[APPLE_ENV.onlineChecks]?.trim().toLowerCase() === "true";

  return {
    config: { bundleId, appAppleId, rootCertificates, environments, enableOnlineChecks },
  };
}

function asMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

/**
 * Apply the Calp Pro entitlement policy to an already-verified, decoded
 * transaction. Verification (signature, certificate chain, bundle id and
 * environment) is Apple's `SignedDataVerifier` responsibility; this function
 * only decides tier from product id, expiry and revocation.
 */
export function evaluateTransactionPayload(
  payload: Pick<JWSTransactionDecodedPayload, "productId" | "expiresDate" | "revocationDate">,
  now: number = Date.now(),
): EntitlementDecision {
  const productID = typeof payload.productId === "string" ? payload.productId : undefined;
  const expiresAt = asMillis(payload.expiresDate);
  const revoked = payload.revocationDate !== undefined && payload.revocationDate !== null;

  if (!productID || !PRO_PRODUCT_IDS.has(productID)) {
    return { tier: "free", verificationFailed: true, reason: "unsupported_product" };
  }
  if (revoked) {
    return { tier: "free", productID, expiresAt, verificationFailed: false, reason: "revoked" };
  }
  if (!expiresAt || expiresAt <= now) {
    return { tier: "free", productID, expiresAt, verificationFailed: false, reason: "expired" };
  }
  return { tier: "pro", productID, expiresAt, verificationFailed: false };
}

function classifyVerificationError(error: unknown): string {
  if (error instanceof VerificationException) {
    switch (error.status) {
      case VerificationStatus.INVALID_APP_IDENTIFIER:
        return "wrong_bundle_id";
      case VerificationStatus.INVALID_ENVIRONMENT:
        return "wrong_environment";
      case VerificationStatus.INVALID_CHAIN_LENGTH:
      case VerificationStatus.INVALID_CERTIFICATE:
        return "invalid_certificate_chain";
      default:
        return "invalid_jws";
    }
  }
  return "invalid_jws";
}

// Injectable so tests can drive verification without reaching Apple's servers.
export type VerifierFactory = (
  environment: Environment,
  config: AppleVerifierConfig,
) => Pick<SignedDataVerifier, "verifyAndDecodeTransaction">;

const defaultVerifierFactory: VerifierFactory = (environment, config) =>
  new SignedDataVerifier(
    config.rootCertificates,
    config.enableOnlineChecks,
    environment,
    config.bundleId,
    config.appAppleId,
  );

/**
 * Verify Apple's StoreKit `signedTransactionInfo` JWS with the official
 * `@apple/app-store-server-library` and map the decoded transaction to a Calp
 * entitlement. Each configured environment is tried in order so a single
 * deployment can serve both Sandbox (TestFlight/dev) and Production users.
 */
export async function verifyAppleTransactionJWS(
  jws: string,
  now: number = Date.now(),
  env: EnvSource = process.env,
  verifierFactory: VerifierFactory = defaultVerifierFactory,
): Promise<EntitlementDecision> {
  const result = loadAppleVerifierConfig(env);
  if ("error" in result) {
    return { tier: "free", verificationFailed: true, reason: result.error };
  }
  const { config } = result;

  let lastReason = "invalid_jws";
  for (const environment of config.environments) {
    if (environment === Environment.PRODUCTION && config.appAppleId === undefined) {
      // Apple's verifier requires the numeric app id to check Production data.
      // Keep this environment out of the trust path but remember why, so a
      // Sandbox-only test deployment still works while a real Production
      // transaction fails closed with a diagnosable reason.
      lastReason = "missing_app_apple_id";
      continue;
    }
    try {
      const verifier = verifierFactory(environment, config);
      const decoded = await verifier.verifyAndDecodeTransaction(jws);
      return evaluateTransactionPayload(decoded, now);
    } catch (error) {
      lastReason = classifyVerificationError(error);
    }
  }
  return { tier: "free", verificationFailed: true, reason: lastReason };
}

export async function resolveEntitlement(
  redis: { get<T = unknown>(key: string): Promise<T | null>; set(key: string, value: string, options: { ex: number }): Promise<unknown> },
  installationHash: string,
  signedTransactionInfo: string | undefined,
  claimedPro: boolean,
  now: number = Date.now(),
): Promise<EntitlementDecision> {
  const key = `calp:entitlement:${installationHash}`;
  // brand-keep: dual-read the pre-rename namespace during the migration window so
  // any debug build cached under the old key keeps its entitlement until TTL
  // expiry. New entries are always written under the calp: namespace below.
  const legacyKey = `calorisor:entitlement:${installationHash}`; // brand-keep
  const cached = (await redis.get<string>(key)) ?? (await redis.get<string>(legacyKey));
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
