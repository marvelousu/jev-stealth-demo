import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:test";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import worker from "../src/index";
import { rulesChoice, validateDecisionRequest } from "../src/contract";

const client = (suffix: number) => `203.0.113.${suffix}`;
const testHash = (suffix: number) => `x${suffix.toString(36).padStart(42, "0")}`;

function payload(changes: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    request_id: "test-1",
    revision: 3,
    trigger: "noise",
    observations: [{ id: "noise-1", fact: "A metal noise was heard near the east crates." }],
    mission: "Protect the relay station and report suspicious activity.",
    candidates: ["inspect", "paired_inspection", "hold_position"],
    mode: "jev",
    ...changes
  };
}

async function decision(body: unknown, ip = client(1)): Promise<Response> {
  return worker.fetch(new Request("https://relay-jev-demo.example/decision", {
    method: "POST",
    headers: { "content-type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify(body)
  }), env);
}

function enabledEnvironment(overrides: Record<string, unknown> = {}): Env {
  const testEnv = Object.create(env) as Env;
  Object.assign(testEnv, { DEMO_ENABLED: "true", ...overrides });
  return testEnv;
}

async function enabledDecision(body: unknown, ip = client(1), overrides: Record<string, unknown> = {}): Promise<Response> {
  return worker.fetch(new Request("https://relay-jev-demo.example/decision", {
    method: "POST",
    headers: { "content-type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify(body)
  }), enabledEnvironment(overrides));
}

afterEach(async () => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  await reset();
});

describe("public demo contract", () => {
  it("the native Workers runtime accepts the non-following redirect policy", () => {
    expect(new Request("https://example.org", { redirect: "manual" }).redirect).toBe("manual");
  });

  it("reports health without exposing the configured secret", async () => {
    const response = await worker.fetch(new Request("https://relay-jev-demo.example/health"), env);
    const health = await response.json() as Record<string, unknown>;
    expect(health).toMatchObject({ service: "jev-stealth-demo", model: "jev-1.13.0", api_key_configured: true, enabled: expect.any(Boolean) });
    expect(JSON.stringify(health)).not.toContain("test-key-not-a-secret");
  });

  it("rejects malformed or oversized decision input before an upstream call", async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    const malformed = await enabledDecision({ ...payload(), unexpected: true });
    expect(malformed.status).toBe(400);
    expect(await malformed.json()).toEqual({ status: "invalid_request" });
    const tooLarge = await worker.fetch(new Request("https://relay-jev-demo.example/decision", {
      method: "POST",
      headers: { "content-type": "application/json", "CF-Connecting-IP": client(2), "content-length": "16385" },
      body: JSON.stringify(payload())
    }), enabledEnvironment());
    expect(tooLarge.status).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("accepts counter_watch as a bounded Jev action without changing the deterministic six-action rules baseline", () => {
    const counterWatch = validateDecisionRequest(payload({
      candidates: ["counter_watch", "inspect", "hold_position"],
      observations: [
        { id: "noise-1", fact: "A repeated metal noise came from the east crates." },
        { id: "route-1", fact: "A guard previously observed trouble near the west corridor route." }
      ]
    }));
    expect(counterWatch.candidates).toContain("counter_watch");
    expect(rulesChoice(counterWatch)).toBe("inspect");

    const omittedExpectedChoice = validateDecisionRequest(payload({
      candidates: ["counter_watch", "inspect", "hold_position"],
      trigger: "contact",
      observations: [{ id: "contact-1", fact: "Contact was reported near the east crates." }]
    }));
    expect(rulesChoice(omittedExpectedChoice)).toBe("inspect");
  });

  it("sends the complete tactical choice contract to Jev and accepts counter_watch", async () => {
    const fetchSpy = vi.fn(async () => new Response(JSON.stringify({
      model: "jev-1.13.0",
      answers: {
        tactical_action: {
          type: "choice",
          choice: "counter_watch",
          confidence: 0.84,
          probabilities: { counter_watch: 0.84, paired_inspection: 0.16 }
        },
        diversion_link: { type: "noul", noul: 0.86 }
      },
      usage: { input_tokens: 123 }
    }), { status: 200 }));
    vi.stubGlobal("fetch", fetchSpy);
    const response = await enabledDecision(payload({
      candidates: ["counter_watch", "paired_inspection"],
      observations: [
        { id: "noise-1", fact: "A repeated noise came from the east crates." },
        { id: "route-1", fact: "The west route was observed as a separate trouble point." }
      ]
    }));
    expect(await response.json()).toMatchObject({ source: "jev", status: "ok", choice: "counter_watch", raw_choice: "counter_watch", diversion_probability: 0.86, confidence: 0.84, input_tokens: 123 });
    const providerRequest = JSON.parse(String(fetchSpy.mock.calls[0][1].body)) as Record<string, any>;
    const tacticalAction = providerRequest.questions.tactical_action;
    expect(tacticalAction.instructions).toContain("reversible, uncertainty-weighted allocation of attention");
    expect(tacticalAction.instructions).toContain("OBSERVED trouble in a DIFFERENT area");
    expect(tacticalAction.criteria.counter_watch).toContain("precautionary coverage, not a claim of known hostile intent");
    expect(providerRequest.state.available_actions).toEqual(["counter_watch", "paired_inspection"]);
    expect(providerRequest.questions.diversion_link).toMatchObject({ type: "noul" });
  });

  it("composes a low diversion Noul with the strongest non-counter choice while retaining Jev's raw choice", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      model: "jev-1.13.0",
      answers: {
        tactical_action: {
          type: "choice",
          choice: "counter_watch",
          confidence: 0.61,
          probabilities: { counter_watch: 0.61, paired_inspection: 0.25, inspect: 0.14 }
        },
        diversion_link: { type: "noul", noul: 0.21 }
      },
      usage: { input_tokens: 127 }
    }), { status: 200 })));
    const response = await enabledDecision(payload({ candidates: ["counter_watch", "inspect", "paired_inspection"] }));
    expect(await response.json()).toMatchObject({
      source: "jev", choice: "paired_inspection", raw_choice: "counter_watch", diversion_probability: 0.21, confidence: 0.61
    });
  });

  it.each([
    ["missing", undefined],
    ["invalid", { type: "noul", noul: 1.01 }]
  ])("rejects a %s diversion Noul when counter_watch is offered", async (_label, diversionLink) => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      model: "jev-1.13.0",
      answers: {
        tactical_action: {
          type: "choice",
          choice: "counter_watch",
          confidence: 0.8,
          probabilities: { counter_watch: 0.8, inspect: 0.2 }
        },
        ...(diversionLink === undefined ? {} : { diversion_link: diversionLink })
      },
      usage: { input_tokens: 120 }
    }), { status: 200 })));
    const response = await enabledDecision(payload({ candidates: ["counter_watch", "inspect"] }));
    expect(await response.json()).toMatchObject({ source: "fallback", status: "api_unavailable_or_invalid" });
    expect(String(errorSpy.mock.calls[0][0])).toContain('"diagnostic":"provider_validation_diversion_link"');
  });

  it("does not require or send a diversion Noul for the older six-action client", async () => {
    const fetchSpy = vi.fn(async () => new Response(JSON.stringify({
      model: "jev-1.13.0",
      answers: {
        tactical_action: {
          type: "choice",
          choice: "inspect",
          confidence: 0.9,
          probabilities: {
            inspect: 0.9,
            paired_inspection: 0.02,
            hold_position: 0.02,
            sweep_last_known: 0.02,
            contain_exits: 0.02,
            flank_and_cover: 0.02
          }
        }
      },
      usage: { input_tokens: 118 }
    }), { status: 200 }));
    vi.stubGlobal("fetch", fetchSpy);
    const response = await enabledDecision(payload({ candidates: ["inspect", "paired_inspection", "hold_position", "sweep_last_known", "contain_exits", "flank_and_cover"] }));
    const decisionResult = await response.json() as Record<string, unknown>;
    expect(decisionResult).toMatchObject({ source: "jev", choice: "inspect" });
    expect(decisionResult).not.toHaveProperty("raw_choice");
    expect(decisionResult).not.toHaveProperty("diversion_probability");
    const providerRequest = JSON.parse(String(fetchSpy.mock.calls[0][1].body)) as { questions: Record<string, unknown> };
    expect(providerRequest.questions).not.toHaveProperty("diversion_link");
  });

  it("uses an explicit fallback when the fixed provider returns an invalid response", async () => {
    const fetchSpy = vi.fn(async () => new Response(JSON.stringify({ model: "wrong-model" }), { status: 200 }));
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", fetchSpy);
    const response = await enabledDecision(payload());
    const result = await response.json() as Record<string, unknown>;
    expect(result).toMatchObject({ source: "fallback", status: "api_unavailable_or_invalid", request_id: "test-1", revision: 3 });
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(fetchSpy.mock.calls[0][0]).toBe("https://api.typesafe.ai/v1/systemone");
    expect(fetchSpy.mock.calls[0][1]).toMatchObject({ redirect: "manual" });
    expect(errorSpy).toHaveBeenCalledOnce();
    expect(JSON.parse(String(errorSpy.mock.calls[0][0]))).toMatchObject({ event: "jev_provider_failure", diagnostic: "provider_validation_model_or_envelope", elapsed_ms: expect.any(Number) });
  });

  it("logs only a numeric provider HTTP diagnostic and returns the normal fallback shape", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("provider body must not be logged", { status: 401 })));
    const response = await enabledDecision(payload());
    expect(await response.json()).toMatchObject({ source: "fallback", status: "api_unavailable_or_invalid" });
    const logged = String(errorSpy.mock.calls[0][0]);
    expect(logged).toContain('"diagnostic":"provider_http_401"');
    expect(logged).not.toContain("provider body must not be logged");
    expect(logged).not.toContain("test-key-not-a-secret");
  });

  it("does not follow provider redirects or log their target", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("https://redirect-target.invalid must not be logged", { status: 302 })));
    const response = await enabledDecision(payload());
    expect(await response.json()).toMatchObject({ source: "fallback", status: "api_unavailable_or_invalid" });
    const logged = String(errorSpy.mock.calls[0][0]);
    expect(logged).toContain('"diagnostic":"provider_redirect"');
    expect(logged).not.toContain("redirect-target.invalid");
  });

  it("rejects malformed secret material before it can call Jev", async () => {
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
    const response = await enabledDecision(payload(), client(7), { TYPESAFE_API_KEY: "\uFEFF \tinvalid key\n" });
    expect(await response.json()).toMatchObject({ source: "fallback", status: "missing_api_key" });
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("keeps concurrent global reservations at three hundred and survives an object eviction", async () => {
    const coordinator = env.BUDGET_COORDINATOR.getByName("relay-jev-demo-budget-v1");
    const timestamp = 1_800_000_000_000;
    await runInDurableObject(coordinator, (_instance, state) => {
      state.storage.sql.exec("INSERT INTO global_minute_attempts(minute_bucket, attempts) VALUES (?, ?)", Math.floor(timestamp / 60_000), 299);
    });
    const reservations = await Promise.all([coordinator.reserve(testHash(1), timestamp), coordinator.reserve(testHash(2), timestamp)]);
    expect(reservations.filter((entry) => entry.allowed)).toHaveLength(1);
    expect(reservations.find((entry) => !entry.allowed)).toEqual({ allowed: false, reason: "global_rate_limited" });
    await evictDurableObject(coordinator);
    expect(await coordinator.reserve(testHash(99), timestamp)).toEqual({ allowed: false, reason: "global_rate_limited" });
  });

  it("caps one hashed client at one hundred twenty upstream attempts per minute", async () => {
    const coordinator = env.BUDGET_COORDINATOR.getByName("relay-jev-demo-budget-v1");
    const timestamp = 1_800_000_100_000;
    await runInDurableObject(coordinator, (_instance, state) => {
      state.storage.sql.exec("INSERT INTO client_minute_attempts(minute_bucket, client_hash, attempts) VALUES (?, ?, ?)", Math.floor(timestamp / 60_000), testHash(42), 119);
    });
    const attempts = await Promise.all([coordinator.reserve(testHash(42), timestamp), coordinator.reserve(testHash(42), timestamp)]);
    expect(attempts.filter((entry) => entry.allowed)).toHaveLength(1);
    expect(attempts.find((entry) => !entry.allowed)).toEqual({ allowed: false, reason: "client_rate_limited" });
  });

  it("enforces seeded daily and lifetime boundaries without repeated API attempts", async () => {
    const timestamp = 1_800_000_200_000;
    const dayBucket = Math.floor(timestamp / 86_400_000);
    const daily = env.BUDGET_COORDINATOR.getByName("daily-boundary");
    await runInDurableObject(daily, (_instance, state) => {
      state.storage.sql.exec("INSERT INTO daily_attempts(day_bucket, attempts) VALUES (?, ?)", dayBucket, 10_000);
    });
    expect(await daily.reserve(testHash(3), timestamp)).toEqual({ allowed: false, reason: "daily_budget_limited" });
    const lifetime = env.BUDGET_COORDINATOR.getByName("lifetime-boundary");
    await runInDurableObject(lifetime, (_instance, state) => {
      state.storage.sql.exec("INSERT INTO meta(key, value) VALUES ('lifetime_attempts', ?)", 100_000);
    });
    expect(await lifetime.reserve(testHash(4), timestamp)).toEqual({ allowed: false, reason: "lifetime_budget_limited" });
  });
});
