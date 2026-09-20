export const SERVICE_NAME = "jev-stealth-demo";
export const MODEL = "jev-1.13.0";
export const ENDPOINT = "https://api.typesafe.ai/v1/systemone";
export const MAX_BODY_BYTES = 16 * 1024;
export const MAX_PROVIDER_REPLY_BYTES = 64 * 1024;
export const REQUEST_TIMEOUT_MS = 3_000;
export const MAX_OBSERVATIONS = 12;
export const MAX_FACT_CHARS = 240;
export const MAX_MISSION_CHARS = 240;
export const MAX_REQUEST_ID_CHARS = 64;

export const ACTION_DESCRIPTIONS = {
  inspect: "For one uncorroborated report, one guard makes a routine check from cover when the other guards can retain critical objective and exit posts.",
  paired_inspection: "Move a second mobile guard from its current post to cover the investigator, who waits before entering. Use this costly reinforcement when observed danger makes a lone check unsafe, such as injury or unresolved hostile activity near the disturbance. Ordinary uncertainty alone is not evidence of that danger. A critical post remains guarded.",
  hold_position: "Keep the current posts and watch the known approaches when the facts do not justify redeploying anyone; repeated empty checks without independent trouble remain a reason for caution, not a chase.",
  sweep_last_known: "Search plausible routes from a lost last-known area, but leave a guard on the critical objective or exit instead of emptying both.",
  contain_exits: "When the case or objective is confirmed missing, protect likely exits and objective routes before a blind chase.",
  flank_and_cover: "During immediate confirmed contact, one guard pressures from cover while a partner takes a useful angle and preserves the critical post where possible.",
  counter_watch: "Make a reversible split of attention under a plausible diversion: one observer watches the disturbance site from cover while a partner watches the previously OBSERVED alternate trouble route; preserve the critical objective or exit guard. This is precautionary coverage, not a claim of known hostile intent."
} as const;

export type Action = keyof typeof ACTION_DESCRIPTIONS;
export type Trigger = "noise" | "report" | "contact" | "lost_contact" | "objective_missing";
export type Mode = "jev" | "rules";

export interface DecisionRequest {
  request_id: string;
  revision: number;
  trigger: Trigger;
  observations: Array<{ id: string; fact: string }>;
  mission: string;
  candidates: Action[];
  mode: Mode;
}

export interface DecisionResult {
  request_id: string;
  revision: number;
  choice: Action;
  source: "jev" | "rules" | "fallback";
  confidence: number | null;
  elapsed_ms: number;
  input_tokens: number;
  status: string;
  // Present only when counter_watch was offered. raw_choice is Jev's Choice
  // result; choice may be composed with diversion_probability, the Noul chance
  // that the observed timeline supports an unresolved cross-area diversion.
  raw_choice?: Action;
  diversion_probability?: number;
}

const ACTIONS = new Set<string>(Object.keys(ACTION_DESCRIPTIONS));
const TRIGGERS = new Set<string>(["noise", "report", "contact", "lost_contact", "objective_missing"]);
const MODES = new Set<string>(["jev", "rules"]);
const ID_PATTERN = /^[A-Za-z0-9._:-]+$/;

export class DecisionError extends Error {}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new DecisionError("expected an object");
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): void {
  const keys = Object.keys(value);
  if (keys.length !== expected.length || keys.some((key) => !expected.includes(key))) {
    throw new DecisionError("unexpected decision contract fields");
  }
}

function text(value: unknown, limit: number, field: string): string {
  if (typeof value !== "string") throw new DecisionError(`${field} must be a string`);
  const cleaned = value.trim();
  if (!cleaned || cleaned.length > limit || /[\u0000-\u001f]/.test(cleaned)) {
    throw new DecisionError(`${field} has an invalid length or control character`);
  }
  return cleaned;
}

function id(value: unknown, limit: number, field: string): string {
  const cleaned = text(value, limit, field);
  if (!ID_PATTERN.test(cleaned)) throw new DecisionError(`${field} has unsupported characters`);
  return cleaned;
}

export function validateDecisionRequest(raw: unknown): DecisionRequest {
  const value = record(raw);
  exactKeys(value, ["request_id", "revision", "trigger", "observations", "mission", "candidates", "mode"]);
  const requestId = id(value.request_id, MAX_REQUEST_ID_CHARS, "request_id");
  if (!Number.isInteger(value.revision) || typeof value.revision !== "number" || value.revision < 0 || value.revision > 2_147_483_647) {
    throw new DecisionError("revision must be a non-negative integer");
  }
  if (typeof value.trigger !== "string" || !TRIGGERS.has(value.trigger)) throw new DecisionError("unsupported trigger");
  if (typeof value.mode !== "string" || !MODES.has(value.mode)) throw new DecisionError("unsupported mode");
  if (!Array.isArray(value.observations) || value.observations.length > MAX_OBSERVATIONS) {
    throw new DecisionError("observations must be a bounded list");
  }
  const seenObservationIds = new Set<string>();
  const observations = value.observations.map((rawObservation) => {
    const observation = record(rawObservation);
    exactKeys(observation, ["id", "fact"]);
    const observationId = id(observation.id, 48, "observation id");
    if (seenObservationIds.has(observationId)) throw new DecisionError("observation id is repeated");
    seenObservationIds.add(observationId);
    return { id: observationId, fact: text(observation.fact, MAX_FACT_CHARS, "observation fact") };
  });
  if (!Array.isArray(value.candidates) || value.candidates.length < 1 || value.candidates.length > ACTIONS.size) {
    throw new DecisionError("candidates must be a non-empty bounded list");
  }
  const candidates = value.candidates.map((candidate) => {
    if (typeof candidate !== "string" || !ACTIONS.has(candidate)) throw new DecisionError("candidate is not in the action enum");
    return candidate as Action;
  });
  if (new Set(candidates).size !== candidates.length) throw new DecisionError("candidates must be unique");
  return {
    request_id: requestId,
    revision: value.revision,
    trigger: value.trigger as Trigger,
    observations,
    mission: text(value.mission, MAX_MISSION_CHARS, "mission"),
    candidates,
    mode: value.mode as Mode
  };
}

export function rulesChoice(request: DecisionRequest): Action {
  let desired: Action = ({
    contact: "flank_and_cover",
    lost_contact: "sweep_last_known",
    objective_missing: "contain_exits",
    report: "paired_inspection",
    noise: "inspect"
  } as const satisfies Record<Trigger, Action>)[request.trigger];
  if (request.trigger === "noise") {
    const facts = request.observations.map((item) => item.fact.toLowerCase()).join(" ");
    if (["empty", "no contact", "previous", "again"].some((marker) => facts.includes(marker))) desired = "paired_inspection";
  }
  if (request.candidates.includes(desired)) return desired;
  // counter_watch is Jev-only for this baseline. An old client must never reach
  // it simply because its expected six-action rule choice was omitted.
  return request.candidates.find((candidate) => candidate !== "counter_watch") ?? request.candidates[0];
}

export function result(
  request: DecisionRequest,
  choice: Action,
  source: DecisionResult["source"],
  confidence: number | null,
  elapsedMs: number,
  inputTokens: number,
  status: string,
  composition?: Pick<DecisionResult, "raw_choice" | "diversion_probability">
): DecisionResult {
  return {
    request_id: request.request_id,
    revision: request.revision,
    choice,
    source,
    confidence,
    elapsed_ms: Math.max(0, Math.round(elapsedMs)),
    input_tokens: inputTokens,
    status,
    ...(composition?.raw_choice === undefined ? {} : { raw_choice: composition.raw_choice }),
    ...(composition?.diversion_probability === undefined ? {} : { diversion_probability: composition.diversion_probability })
  };
}

export function fallback(request: DecisionRequest, status: string, elapsedMs = 0): DecisionResult {
  return result(request, rulesChoice(request), "fallback", null, elapsedMs, 0, status);
}
