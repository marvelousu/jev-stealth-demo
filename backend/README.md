# Relay Jev demo backend

This Worker is the only Jev credential boundary for the distributable Relay stealth demo. The Godot build calls only `GET /health` and `POST /decision`; it never receives a TypeSafe API key and cannot choose an upstream URL, model, question, or action outside the fixed contract.

`DemoBudgetCoordinator` is one SQLite-backed Durable Object for this one demo's shared spending limits. It atomically reserves an attempt before the Worker makes its only outbound call, then the Worker calls Jev after the Durable Object response has returned. A timeout or invalid provider reply is still counted. The object keeps a lifetime cap of 100,000 attempts, a UTC-day cap of 10,000, a global 300-attempt minute cap, and a 120-attempt minute cap per SHA-256-hashed Cloudflare client IP. It keeps only the current and previous time buckets, so raw IP addresses and unbounded historical rate records are not stored.

The response always has the game decision shape:

```json
{
  "request_id": "event-7",
  "revision": 7,
  "choice": "inspect",
  "source": "jev",
  "confidence": 0.73,
  "elapsed_ms": 211,
  "input_tokens": 188,
  "status": "ok"
}
```

Failure and stop conditions keep the game playable through its normal rule AI: `demo_disabled`, `missing_api_key`, `rate_or_budget_limited`, `api_unavailable_or_invalid`, and (in production when Cloudflare does not provide a client IP) `client_ip_required` return `source: "fallback"`. `mode: "rules"` never calls Jev or consumes an attempt. `GET /health` reports `service`, `model`, `api_key_configured`, and `enabled`, without returning a credential.

## Operator setup

Deploying without a key is intentional: it starts safely in the `missing_api_key` fallback state. Set the `TYPESAFE_API_KEY` Worker secret in the Cloudflare dashboard after the first deployment. It is absent from `wrangler.jsonc`, source, local test output, and the game distribution.

`DEMO_ENABLED=true` is a non-secret Worker variable. Change it to `false` in the Cloudflare dashboard and deploy/save the variable to stop all future Jev calls while preserving normal enemy AI. `DEPLOYMENT_ENV=production` requires Cloudflare's `CF-Connecting-IP`; do not loosen that setting for the public Worker.

For the prepared candidate:

```powershell
npm ci
npm run check
npm run dry-run
```

`npm run test` uses Cloudflare's Workers Vitest pool and SQLite-backed Durable Object simulation. It covers malformed input, secret-free health output, invalid-provider fallback, concurrent global cap, per-client cap, daily and lifetime boundaries seeded directly in SQLite, and persistence after an object eviction. It does not call TypeSafe or deploy a Worker.

The Workers test pool pins older Wrangler/Miniflare builds internally. `package.json` overrides them to the same updated runtime used by this repository. Run `npm ci`, `npm run check`, `npm run dry-run`, and `npm audit` together when changing these versions.
