import { DurableObject } from "cloudflare:workers";
import {
  ACTION_DESCRIPTIONS,
  ENDPOINT,
  MAX_BODY_BYTES,
  MAX_PROVIDER_REPLY_BYTES,
  MODEL,
  REQUEST_TIMEOUT_MS,
  SERVICE_NAME,
  DecisionError,
  type Action,
  type DecisionRequest,
  fallback,
  result,
  rulesChoice,
  validateDecisionRequest
} from "./contract";

const GLOBAL_REQUESTS_PER_MINUTE = 300;
const REQUESTS_PER_CLIENT_PER_MINUTE = 120;
const MAX_DAILY_API_ATTEMPTS = 10_000;
const MAX_LIFETIME_API_ATTEMPTS = 100_000;
const UTF8 = new TextEncoder();

type ReserveReason = "allowed" | "global_rate_limited" | "client_rate_limited" | "daily_budget_limited" | "lifetime_budget_limited";
interface Reservation { allowed: boolean; reason: ReserveReason; }
interface ProviderChoice {
  choice: Action;
  rawChoice?: Action;
  diversionProbability?: number;
  confidence: number;
  inputTokens: number;
}

// These are intentionally fixed, non-secret diagnostics. Never derive one
// from a provider body, header, API key, or thrown error message.
type ProviderDiagnostic =
  | "provider_timeout"
  | "provider_network_failure"
  | "provider_redirect"
  | "provider_empty_body"
  | "provider_response_too_large"
  | "provider_response_invalid_json"
  | "provider_validation_not_object"
  | "provider_validation_model_or_envelope"
  | "provider_validation_choice"
  | "provider_validation_probabilities"
  | "provider_validation_diversion_link"
  | "provider_validation_usage"
  | "provider_internal_failure"
  | `provider_http_${number}`;

class ProviderFailure extends Error {
  constructor(readonly diagnostic: ProviderDiagnostic) {
    super(diagnostic);
  }
}

export class DemoBudgetCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS daily_attempts (day_bucket INTEGER PRIMARY KEY, attempts INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS global_minute_attempts (minute_bucket INTEGER PRIMARY KEY, attempts INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS client_minute_attempts (
          minute_bucket INTEGER NOT NULL,
          client_hash TEXT NOT NULL,
          attempts INTEGER NOT NULL,
          PRIMARY KEY (minute_bucket, client_hash)
        );
      `);
    });
  }

  reserve(clientHash: string, nowMs = Date.now()): Reservation {
    if (!/^[A-Za-z0-9_-]{43}$/.test(clientHash) || !Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new Error("invalid reservation input");
    }
    const minuteBucket = Math.floor(nowMs / 60_000);
    const dayBucket = Math.floor(nowMs / 86_400_000);
    return this.ctx.storage.transactionSync(() => {
      const sql = this.ctx.storage.sql;
      // Keep only current and immediately previous buckets. The remaining tables
      // are bounded by the active player count rather than all historical IPs.
      sql.exec("DELETE FROM client_minute_attempts WHERE minute_bucket < ?", minuteBucket - 1);
      sql.exec("DELETE FROM global_minute_attempts WHERE minute_bucket < ?", minuteBucket - 1);
      sql.exec("DELETE FROM daily_attempts WHERE day_bucket < ?", dayBucket - 1);
      const lifetime = numberColumn(sql.exec<{ value: number }>("SELECT value FROM meta WHERE key = 'lifetime_attempts'").toArray()[0], "value");
      if (lifetime >= MAX_LIFETIME_API_ATTEMPTS) return { allowed: false, reason: "lifetime_budget_limited" };
      const daily = numberColumn(sql.exec<{ attempts: number }>("SELECT attempts FROM daily_attempts WHERE day_bucket = ?", dayBucket).toArray()[0], "attempts");
      if (daily >= MAX_DAILY_API_ATTEMPTS) return { allowed: false, reason: "daily_budget_limited" };
      const global = numberColumn(sql.exec<{ attempts: number }>("SELECT attempts FROM global_minute_attempts WHERE minute_bucket = ?", minuteBucket).toArray()[0], "attempts");
      if (global >= GLOBAL_REQUESTS_PER_MINUTE) return { allowed: false, reason: "global_rate_limited" };
      const client = numberColumn(sql.exec<{ attempts: number }>("SELECT attempts FROM client_minute_attempts WHERE minute_bucket = ? AND client_hash = ?", minuteBucket, clientHash).toArray()[0], "attempts");
      if (client >= REQUESTS_PER_CLIENT_PER_MINUTE) return { allowed: false, reason: "client_rate_limited" };

      sql.exec("INSERT INTO meta(key, value) VALUES ('lifetime_attempts', 1) ON CONFLICT(key) DO UPDATE SET value = value + 1");
      sql.exec("INSERT INTO daily_attempts(day_bucket, attempts) VALUES (?, 1) ON CONFLICT(day_bucket) DO UPDATE SET attempts = attempts + 1", dayBucket);
      sql.exec("INSERT INTO global_minute_attempts(minute_bucket, attempts) VALUES (?, 1) ON CONFLICT(minute_bucket) DO UPDATE SET attempts = attempts + 1", minuteBucket);
      sql.exec("INSERT INTO client_minute_attempts(minute_bucket, client_hash, attempts) VALUES (?, ?, 1) ON CONFLICT(minute_bucket, client_hash) DO UPDATE SET attempts = attempts + 1", minuteBucket, clientHash);
      return { allowed: true, reason: "allowed" };
    });
  }
}

function numberColumn(row: Record<string, unknown> | undefined, key: string): number {
  const value = row?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

async function readBoundedJson(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null && (!/^\d+$/.test(declaredLength) || Number(declaredLength) < 1 || Number(declaredLength) > MAX_BODY_BYTES)) {
    throw new DecisionError("invalid request length");
  }
  if (!request.body) throw new DecisionError("missing request body");
  const bytes = await readBoundedBytes(request.body, MAX_BODY_BYTES, REQUEST_TIMEOUT_MS);
  if (bytes.byteLength < 1) throw new DecisionError("empty request body");
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    throw new DecisionError("invalid JSON");
  }
}

async function readBoundedBytes(body: ReadableStream<Uint8Array>, maximum: number, timeoutMs?: number): Promise<Uint8Array> {
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  const readAll = (async () => {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      length += next.value.byteLength;
      if (length > maximum) {
        void reader.cancel("body too large").catch(() => undefined);
        throw new RangeError("body too large");
      }
      chunks.push(next.value);
    }
    const joined = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      joined.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return joined;
  })();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    if (timeoutMs === undefined) return await readAll;
    const timedOut = new Promise<never>((_resolve, reject) => {
      timeout = setTimeout(() => {
        void reader.cancel("body read timed out").catch(() => undefined);
        reject(new DecisionError("body read timed out"));
      }, timeoutMs);
    });
    return await Promise.race([readAll, timedOut]);
  } finally {
    if (timeout !== undefined) clearTimeout(timeout);
    readAll.finally(() => reader.releaseLock()).catch(() => undefined);
  }
}

function json(payload: unknown, status = 200): Response {
  return Response.json(payload, { status, headers: { "cache-control": "no-store" } });
}

function isEnabled(env: Env): boolean {
  const enabled = Reflect.get(env, "DEMO_ENABLED") as unknown;
  return enabled === "true";
}

// Wrangler secrets are intentionally absent from versioned configuration. Read
// this runtime-only binding without extending the generated Env declaration.
function configuredApiKey(env: Env): string | undefined {
  const value = Reflect.get(env, "TYPESAFE_API_KEY");
  if (typeof value !== "string") return undefined;
  // PowerShell/stdin can prefix UTF-8 text with a BOM. Normalize only outer
  // whitespace and that prefix, then reject every non-printable/non-ASCII or
  // whitespace-bearing value before it can reach an Authorization header.
  const normalized = value.replace(/^\uFEFF/, "").trim();
  return /^[\x21-\x7e]+$/.test(normalized) ? normalized : undefined;
}

async function clientHash(request: Request, env: Env): Promise<string | null> {
  const clientIp = request.headers.get("CF-Connecting-IP");
  if (!clientIp) return env.DEPLOYMENT_ENV === "production" ? null : hash("development-client");
  return hash(clientIp);
}

async function hash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", UTF8.encode(value));
  return bytesToBase64Url(new Uint8Array(digest));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function evaluateWithJev(request: DecisionRequest, apiKey: string): Promise<ProviderChoice> {
  const aborter = new AbortController();
  const timeout = setTimeout(() => aborter.abort(), REQUEST_TIMEOUT_MS);
  try {
    let response: Response;
    try {
      response = await fetch(ENDPOINT, {
        method: "POST",
        headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({
          model: MODEL,
          state: {
            trigger: request.trigger,
            mission: request.mission,
            observations: request.observations,
            available_actions: request.candidates
          },
          questions: {
            tactical_action: {
              type: "choice",
              instructions: [
                "Choose the most appropriate next tactical posture using only the observed facts and the available actions.",
                "Do not assert an unseen intruder position, intent, route, or ally status as fact; this does not forbid a reversible, uncertainty-weighted allocation of attention.",
                "Immediate confirmed contact can justify flank_and_cover; a case or objective confirmed missing can justify contain_exits; a lost last-known contact without confirmed theft can justify sweep_last_known.",
                "counter_watch is a reversible split of attention under a plausible diversion, not a claim of known hostile intent. A repeated disturbance plus intervening OBSERVED trouble in a DIFFERENT area can justify preserving sight on both areas even when no actor was seen. Repeated empty inspection without independent trouble should remain cautious or hold rather than imply a chase.",
                "paired_inspection means the investigator waits for supporting cover before entering. Every choice must preserve a critical objective or exit guard when the observations identify one.",
                "Use a proportionate response: moving support also removes mobile coverage from its previous post. Weigh that opportunity cost against observed danger, rather than treating every ambiguous sound as a reason to concentrate the team.",
                "Choose exactly one available action. Do not treat the trigger label as proof that any one action is required."
              ].join(" "),
              criteria: Object.fromEntries(request.candidates.map((candidate) => [candidate, ACTION_DESCRIPTIONS[candidate]]))
            },
            ...(request.candidates.includes("counter_watch") ? {
              diversion_link: {
                type: "noul",
                instructions: "Does the observed timeline support a POSSIBLE link between a recurring disturbance in one area and still-unresolved hostile activity in a DIFFERENT area? A high answer requires recurrence plus intervening observed trouble while both areas remain unresolved; uncertainty about intent is allowed. Same-location danger, or a separate incident explicitly cleared or neutralized, means no.",
                criteria: {
                  true: "The facts support reversible cross-area coverage as a precaution because recurring disturbance and intervening trouble remain unresolved in different areas.",
                  false: "The facts only describe same-area danger, an explicitly resolved separate incident, or ordinary repeated empty checks without independent unresolved trouble."
                }
              }
            } : {})
          }
        }),
        signal: aborter.signal,
        // Workers supports manual/follow. Manual makes every 3xx observable
        // without forwarding the Authorization header to a redirect target.
        redirect: "manual"
      });
    } catch {
      throw new ProviderFailure(aborter.signal.aborted ? "provider_timeout" : "provider_network_failure");
    }
    if (response.status >= 300 && response.status < 400) throw new ProviderFailure("provider_redirect");
    if (!response.ok) throw new ProviderFailure(`provider_http_${response.status}`);
    if (!response.body) throw new ProviderFailure("provider_empty_body");
    let bytes: Uint8Array;
    try {
      bytes = await readBoundedBytes(response.body, MAX_PROVIDER_REPLY_BYTES);
    } catch (error) {
      if (error instanceof RangeError) throw new ProviderFailure("provider_response_too_large");
      throw new ProviderFailure(aborter.signal.aborted ? "provider_timeout" : "provider_network_failure");
    }
    let decoded: unknown;
    try {
      decoded = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
    } catch {
      throw new ProviderFailure("provider_response_invalid_json");
    }
    return validateProviderChoice(decoded, request.candidates);
  } finally {
    clearTimeout(timeout);
  }
}

function validateProviderChoice(raw: unknown, candidates: Action[]): ProviderChoice {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new ProviderFailure("provider_validation_not_object");
  const payload = raw as Record<string, unknown>;
  if (payload.model !== MODEL || typeof payload.answers !== "object" || payload.answers === null || Array.isArray(payload.answers) || typeof payload.usage !== "object" || payload.usage === null || Array.isArray(payload.usage)) {
    throw new ProviderFailure("provider_validation_model_or_envelope");
  }
  const answer = (payload.answers as Record<string, unknown>).tactical_action;
  const usage = payload.usage as Record<string, unknown>;
  if (typeof answer !== "object" || answer === null || Array.isArray(answer)) throw new ProviderFailure("provider_validation_choice");
  const choice = answer as Record<string, unknown>;
  if (choice.type !== "choice" || typeof choice.choice !== "string" || !candidates.includes(choice.choice as Action) || typeof choice.confidence !== "number" || !Number.isFinite(choice.confidence) || choice.confidence < 0 || choice.confidence > 1) {
    throw new ProviderFailure("provider_validation_choice");
  }
  if (typeof choice.probabilities !== "object" || choice.probabilities === null || Array.isArray(choice.probabilities)) throw new ProviderFailure("provider_validation_probabilities");
  const probabilities = choice.probabilities as Record<string, unknown>;
  if (Object.keys(probabilities).length !== candidates.length || candidates.some((candidate) => typeof probabilities[candidate] !== "number" || !Number.isFinite(probabilities[candidate]) || (probabilities[candidate] as number) < 0 || (probabilities[candidate] as number) > 1)) {
    throw new ProviderFailure("provider_validation_probabilities");
  }
  const probabilitySum = Object.values(probabilities).reduce<number>((total, probability) => total + (probability as number), 0);
  if (Math.abs(probabilitySum - 1) > 0.02) throw new ProviderFailure("provider_validation_probabilities");
  if (!Number.isInteger(usage.input_tokens) || typeof usage.input_tokens !== "number" || usage.input_tokens < 0 || usage.input_tokens > 4_000) {
    throw new ProviderFailure("provider_validation_usage");
  }
  const rawChoice = choice.choice as Action;
  if (!candidates.includes("counter_watch")) return { choice: rawChoice, confidence: choice.confidence, inputTokens: usage.input_tokens };
  const diversionLink = (payload.answers as Record<string, unknown>).diversion_link;
  if (typeof diversionLink !== "object" || diversionLink === null || Array.isArray(diversionLink)) throw new ProviderFailure("provider_validation_diversion_link");
  const noul = diversionLink as Record<string, unknown>;
  if (noul.type !== "noul" || typeof noul.noul !== "number" || !Number.isFinite(noul.noul) || noul.noul < 0 || noul.noul > 1) {
    throw new ProviderFailure("provider_validation_diversion_link");
  }
  const diversionProbability = noul.noul;
  const composedChoice = rawChoice === "counter_watch" && diversionProbability < 0.65
    ? highestProbabilityNonCounter(candidates, probabilities) ?? rawChoice
    : rawChoice;
  return { choice: composedChoice, rawChoice, diversionProbability, confidence: choice.confidence, inputTokens: usage.input_tokens };
}

function highestProbabilityNonCounter(candidates: Action[], probabilities: Record<string, unknown>): Action | undefined {
  let best: Action | undefined;
  let bestProbability = -1;
  for (const candidate of candidates) {
    if (candidate === "counter_watch") continue;
    const probability = probabilities[candidate];
    if (typeof probability === "number" && probability > bestProbability) {
      best = candidate;
      bestProbability = probability;
    }
  }
  return best;
}

async function decide(request: DecisionRequest, env: Env, originalRequest: Request): Promise<ReturnType<typeof result>> {
  if (request.mode === "rules") return result(request, rulesChoice(request), "rules", null, 0, 0, "rules_mode");
  if (!isEnabled(env)) return fallback(request, "demo_disabled");
  const apiKey = configuredApiKey(env);
  if (!apiKey) return fallback(request, "missing_api_key");
  const identity = await clientHash(originalRequest, env);
  if (!identity) return fallback(request, "client_ip_required");
  const reservation = await env.BUDGET_COORDINATOR.getByName("relay-jev-demo-budget-v1").reserve(identity);
  if (!reservation.allowed) return fallback(request, "rate_or_budget_limited");
  const started = Date.now();
  try {
    const provider = await evaluateWithJev(request, apiKey);
    return result(request, provider.choice, "jev", provider.confidence, Date.now() - started, provider.inputTokens, "ok", {
      raw_choice: provider.rawChoice,
      diversion_probability: provider.diversionProbability
    });
  } catch (error) {
    const diagnostic: ProviderDiagnostic = error instanceof ProviderFailure ? error.diagnostic : "provider_internal_failure";
    console.error(JSON.stringify({ event: "jev_provider_failure", diagnostic, elapsed_ms: Math.max(0, Date.now() - started) }));
    return fallback(request, "api_unavailable_or_invalid", Date.now() - started);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      return json({ service: SERVICE_NAME, model: MODEL, api_key_configured: Boolean(configuredApiKey(env)), enabled: isEnabled(env) });
    }
    if (url.pathname !== "/decision") return json({ status: "not_found" }, 404);
    if (request.method !== "POST") return json({ status: "method_not_allowed" }, 405);
    if (request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
      return json({ status: "json_content_type_required" }, 400);
    }
    try {
      const decisionRequest = validateDecisionRequest(await readBoundedJson(request));
      return json(await decide(decisionRequest, env, request));
    } catch (error) {
      if (error instanceof DecisionError || error instanceof RangeError || error instanceof SyntaxError) return json({ status: "invalid_request" }, 400);
      console.error(JSON.stringify({ event: "decision_request_failure", path: "/decision" }));
      return json({ status: "service_unavailable" }, 503);
    }
  }
} satisfies ExportedHandler<Env>;
