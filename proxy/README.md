# Calp AI Proxy

Vercel Edge Function that keeps the OpenAI API key out of the iOS app. Raw meal
text and images are processed transiently and are not stored. Successful,
normalized model responses are cached in Upstash Redis for up to seven days.

## Local setup

1. Install dependencies with `npm install`.
2. Copy `.env.example` to `.env.local` and fill in both values.
3. Start the function with `npm run dev`.

The endpoint is available at `http://localhost:3000/api/scan`.

## Environment variables

- `OPENAI_API_KEY`: server-side OpenAI API key.
- `CALP_CLIENT_KEY`: shared client key expected in the `x-calp-key` header.
- `UPSTASH_REDIS_REST_URL`: Upstash Redis REST endpoint.
- `UPSTASH_REDIS_REST_TOKEN`: Upstash Redis REST token.
- `INSTALLATION_HASH_SALT`: secret salt hashed with the anonymous installation id
  (`x-calp-installation-id`) to derive the rate-limit key. Required; the
  function returns HTTP 502 when it is unset. The raw installation id is never
  logged or stored — only its salted SHA-256 hash is used.
- `REQUIRE_INSTALLATION_ID` (optional): set to `true` to reject requests that
  omit the installation id header with HTTP 400 instead of falling back to a
  hashed IP. Leave unset during the rollout while older clients may still omit it.

Configure the same values in the Vercel project for deployment. Never commit
real keys.

## Apple StoreKit (Calp Pro) verification

Pro entitlement is decided server-side. The iOS app sends the StoreKit
`signedTransactionInfo` JWS in the `signed_transaction_info` field; the proxy
verifies it with Apple's official
[`@apple/app-store-server-library`](https://github.com/apple/app-store-server-library-node)
(`SignedDataVerifier`) — signature, certificate chain up to Apple's root, bundle
id and environment — then applies the Pro product policy. Pro product ids:
`com.fatih.calp.monthly`, `com.fatih.calp.annual` (the pre-rename
`com.fatih.calorisor.*` ids stay entitled via the legacy allowlist).

> **Runtime note:** because the Apple library uses Node's `crypto`
> (`X509Certificate`), `api/scan.ts` and `api/weekly-report.ts` run on the
> **Node.js** runtime (`runtime: "nodejs"`), not Edge.

### Environment variables

| Variable | Required | Example | Notes |
| --- | --- | --- | --- |
| `APPLE_ROOT_CERTIFICATES` | Yes | `MIICQz...` | Base64 DER of Apple Root CA - G3. Comma/newline separated for multiple. Missing ⇒ every verification fails closed to free. |
| `APPLE_BUNDLE_ID` | Recommended | `com.fatih.calp` | Bundle id the transaction must be signed for. Defaults to `com.fatih.calp`. |
| `APPLE_STOREKIT_ENVIRONMENT` | Recommended | `Sandbox` | `Sandbox`, `Production`, or `Production,Sandbox`. Unset ⇒ both (Production first, then Sandbox). |
| `APPLE_APP_APPLE_ID` | Prod only | `6790000000` | Numeric App Store app id (adamId). **Required** to verify Production; unused in Sandbox. |
| `APPLE_ENABLE_ONLINE_CHECKS` | No | `false` | `true` turns on OCSP revocation + live-date checks (needs outbound egress). Default off. |

### Sandbox vs Production

- **Sandbox** — TestFlight and Xcode/dev installs always produce Sandbox
  transactions. Set `APPLE_STOREKIT_ENVIRONMENT=Sandbox`; no `APPLE_APP_APPLE_ID`
  needed. This is the value to use while running the pre-launch Sandbox test.
- **Production** — App Store installs produce Production transactions. Set
  `APPLE_STOREKIT_ENVIRONMENT=Production` **and** `APPLE_APP_APPLE_ID` (the
  numeric app id from App Store Connect → App Information → *Apple ID*).
- **Both** — a single deployment serving TestFlight and App Store users at once
  can use `Production,Sandbox` (requires `APPLE_APP_APPLE_ID`); each transaction
  is tried against Production first, then Sandbox.

If Production is requested without `APPLE_APP_APPLE_ID`, Production transactions
fail closed with reason `missing_app_apple_id` (Sandbox still works). If
`APPLE_ROOT_CERTIFICATES` is unset, all verification fails closed with reason
`missing_certificate_configuration`.

### Preparing the Apple root certificate value

1. Download **Apple Root CA - G3 Root Certificate** (`AppleRootCA-G3.cer`, DER)
   from <https://www.apple.com/certificateauthority/>.
2. Base64-encode it to a single line:

   ```bash
   base64 -i AppleRootCA-G3.cer | tr -d '\n'
   ```

3. Paste the output as the `APPLE_ROOT_CERTIFICATES` value. The certificate is
   public (not a secret), but it is what pins the trust chain, so keep it under
   config control rather than fetching it at runtime.

## Text-mode smoke test

```bash
curl --request POST http://localhost:3000/api/scan \
  --header 'content-type: application/json' \
  --header 'x-calp-key: replace-with-local-client-key' \
  --data '{
    "text": "2 kepçe mercimek çorbası",
    "mode": "text",
    "locale": "tr_TR",
    "tier": "free",
    "schema_version": 1,
    "app_version": "1.0"
  }'
```

A successful response is the `VisionResponse` JSON object itself. The
`x-calp-cache` response header is `miss` for a new analysis and `hit` when the
same normalized text or photo payload is served from the seven-day cache.

Authorized requests are limited per anonymized installation hash (a salted
SHA-256 of the `x-calp-installation-id` header), falling back to a hashed
IP for clients that do not send it. A shared burst ceiling of 10 requests per
minute remains in place; daily pools are 1 photo + 2 text/voice scans for free
users and 50 photo + 100 text/voice scans for pro users. Redis contains SHA-256
cache/rate-limit identifiers, counters, and the normalized model response
associated with a cache identifier. Raw meal text, image data, IP addresses, and
installation ids are not logged. Cache entries expire after seven days.

## App Store privacy nutrition label draft

- Raw photos and meal text: sent only to perform the requested analysis,
  processed transiently, and not persisted by the Calp proxy.
- IP address: not stored in raw form; a SHA-256-derived identifier is retained
  only in expiring rate-limit counters.
- Analysis result: the normalized food and nutrition response is cached against
  an irreversible request hash for up to seven days to avoid repeat AI calls.
- Tracking, advertising, third-party analytics, and account/profile collection:
  none.

The intended App Store declaration is "data not linked to the user" and "not
used for tracking." Do not select the blanket "data not collected" answer
without resolving the seven-day response cache with the final privacy-policy
review; Apple may classify the cached analysis result as collected User Content
even though the raw photo/text is not retained.

Requests with an invalid `x-calp-key` return HTTP 401. Invalid bodies return
HTTP 400, OpenAI rate limits return HTTP 429, and other upstream failures return
HTTP 502.
