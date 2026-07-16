// Test-only helper: builds a self-consistent Apple-style certificate chain
// (root → WWDR intermediate → leaf) carrying the exact extension OIDs Apple's
// SignedDataVerifier requires, and signs StoreKit-shaped JWS transactions with
// it. This lets the entitlement tests exercise the *real* verifier end to end
// without reaching Apple's servers — the only substitution is a locally trusted
// root in place of Apple Root CA - G3.
//
// Not imported by any runtime code path; only the *.test.ts files use it.
import jwt from "jsonwebtoken";
import rs from "jsrsasign";

// Apple's marker extension OIDs. verifyCertificateChainWithoutCaching requires
// the leaf to carry 1.2.840.113635.100.6.11.1 and the intermediate
// 1.2.840.113635.100.6.2.1, so the generated chain must include them.
const LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";
const NULL_EXTENSION_VALUE = { null: "" };

interface KeyPair {
  prvPem: string;
  pubPem: string;
}

function generateKeyPair(): KeyPair {
  const generated = rs.KEYUTIL.generateKeypair("EC", "secp256r1");
  return {
    prvPem: rs.KEYUTIL.getPEM(generated.prvKeyObj, "PKCS8PRV"),
    pubPem: rs.KEYUTIL.getPEM(generated.pubKeyObj),
  };
}

function pemToDerBase64(pem: string): string {
  return pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
}

// deno-lint-ignore no-explicit-any
function buildCertificate(params: Record<string, unknown>): string {
  return new (rs.KJUR.asn1.x509.Certificate as any)(params).getPEM();
}

export interface AppleTestChain {
  /** Base64 DER of the trusted root, for APPLE_ROOT_CERTIFICATES. */
  rootCertificateBase64: string;
  /** Sign a StoreKit transaction JWS with the leaf key + full x5c chain. */
  signTransaction(payload: Record<string, unknown>): string;
  /** Sign a JWS whose signature does NOT match the embedded leaf certificate. */
  signWithForeignKey(payload: Record<string, unknown>): string;
}

export function createAppleTestChain(): AppleTestChain {
  const root = generateKeyPair();
  const intermediate = generateKeyPair();
  const leaf = generateKeyPair();
  const foreign = generateKeyPair();

  const notbefore = "200101000000Z";
  const notafter = "400101000000Z";
  const sigalg = "SHA256withECDSA";

  const rootPem = buildCertificate({
    serial: { int: 1 },
    issuer: { str: "/CN=Calp Test Root CA" },
    subject: { str: "/CN=Calp Test Root CA" },
    notbefore,
    notafter,
    sigalg,
    sbjpubkey: root.pubPem,
    cakey: root.prvPem,
    ext: [{ extname: "basicConstraints", cA: true, critical: true }],
  });

  const intermediatePem = buildCertificate({
    serial: { int: 2 },
    issuer: { str: "/CN=Calp Test Root CA" },
    subject: { str: "/CN=Calp Test WWDR Intermediate" },
    notbefore,
    notafter,
    sigalg,
    sbjpubkey: intermediate.pubPem,
    cakey: root.prvPem,
    ext: [
      { extname: "basicConstraints", cA: true, critical: true },
      { extname: INTERMEDIATE_MARKER_OID, extn: NULL_EXTENSION_VALUE },
    ],
  });

  const leafPem = buildCertificate({
    serial: { int: 3 },
    issuer: { str: "/CN=Calp Test WWDR Intermediate" },
    subject: { str: "/CN=Calp Test Leaf" },
    notbefore,
    notafter,
    sigalg,
    sbjpubkey: leaf.pubPem,
    cakey: intermediate.prvPem,
    ext: [{ extname: LEAF_MARKER_OID, extn: NULL_EXTENSION_VALUE }],
  });

  const x5c = [pemToDerBase64(leafPem), pemToDerBase64(intermediatePem), pemToDerBase64(rootPem)];

  return {
    rootCertificateBase64: pemToDerBase64(rootPem),
    signTransaction(payload) {
      return jwt.sign(payload, leaf.prvPem, {
        algorithm: "ES256",
        header: { alg: "ES256", x5c },
      });
    },
    signWithForeignKey(payload) {
      // Same embedded x5c leaf, but signed with an unrelated key → the
      // certificate chain is valid yet the JWS signature does not verify.
      return jwt.sign(payload, foreign.prvPem, {
        algorithm: "ES256",
        header: { alg: "ES256", x5c },
      });
    },
  };
}

/** A StoreKit transaction payload with sensible defaults, overridable per test. */
export function transactionPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const now = Date.now();
  return {
    bundleId: "com.fatih.calp",
    productId: "com.fatih.calp.monthly",
    environment: "Sandbox",
    transactionId: "1000000000000001",
    originalTransactionId: "1000000000000001",
    purchaseDate: now,
    signedDate: now,
    expiresDate: now + 30 * 24 * 60 * 60 * 1000,
    ...overrides,
  };
}
