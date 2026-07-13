# Sofra AI Proxy

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
- `SOFRA_CLIENT_KEY`: shared client key expected in the `x-sofra-key` header.
- `UPSTASH_REDIS_REST_URL`: Upstash Redis REST endpoint.
- `UPSTASH_REDIS_REST_TOKEN`: Upstash Redis REST token.

Configure the same values in the Vercel project for deployment. Never commit
real keys.

## Text-mode smoke test

```bash
curl --request POST http://localhost:3000/api/scan \
  --header 'content-type: application/json' \
  --header 'x-sofra-key: replace-with-local-client-key' \
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
`x-sofra-cache` response header is `miss` for a new analysis and `hit` when the
same normalized text or photo payload is served from the seven-day cache.

Authorized requests are limited per anonymized IP hash to 10 per minute and
200 per day. Redis contains SHA-256 cache/rate-limit identifiers, counters, and
the normalized model response associated with a cache identifier. Raw meal
text, image data, and IP addresses are not logged. Cache entries expire after
seven days.

## App Store privacy nutrition label draft

- Raw photos and meal text: sent only to perform the requested analysis,
  processed transiently, and not persisted by the Sofra proxy.
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

Requests with an invalid `x-sofra-key` return HTTP 401. Invalid bodies return
HTTP 400, OpenAI rate limits return HTTP 429, and other upstream failures return
HTTP 502.
