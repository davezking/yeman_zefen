// Tunables the app reads from GET /v1/config. Set as Worker vars (wrangler.toml), so changing one
// means a redeploy; the app picks it up on its next start. Spec: docs/phase-3-sprint-2-prompts.md.
import { z } from "zod";
import type { Bindings } from "../env";
import { ApiError } from "./errors";

export type RemoteConfig = {
  /** A round with an interstitial ad after every this many rounds. */
  interstitialEveryRounds: number;
  /** Guest players are asked to register after this many completed sessions (FR-13). */
  registerPromptAfterSessions: number;
  /** After a dismissed register prompt, wait this many days before asking again. */
  registerPromptCooldownDays: number;
  /** Apps older than this (semver `major.minor.patch`) must update before they play. */
  minAppVersion: string;
  /** Clip length a round uses by default, in ms. */
  defaultClipMs: number;
};

const version = z.string().regex(/^\d+\.\d+\.\d+$/, "must look like 1.2.3");
// Digits only: coercing would read "" or " " as 0 and "1e3" as 1000.
const whole = (min: number, max: number) =>
  z.string().regex(/^\d+$/, "must be a whole number").transform(Number).pipe(z.number().min(min).max(max));

// The vars as wrangler sets them (strings). A bad value is a 500 that names the var: the app then
// keeps its cached or built-in values, so a typo must be loud here rather than silently default.
const VARS = {
  interstitialEveryRounds: ["CONFIG_INTERSTITIAL_EVERY_ROUNDS", whole(1, 1000)],
  registerPromptAfterSessions: ["CONFIG_REGISTER_PROMPT_AFTER_SESSIONS", whole(0, 1000)],
  registerPromptCooldownDays: ["CONFIG_REGISTER_PROMPT_COOLDOWN_DAYS", whole(0, 1000)],
  minAppVersion: ["CONFIG_MIN_APP_VERSION", version],
  defaultClipMs: ["CONFIG_DEFAULT_CLIP_MS", whole(1000, 60_000)],
} as const;

/** The current config, read from the Worker's vars. */
export function remoteConfig(env: Bindings): RemoteConfig {
  const out: Record<string, unknown> = {};
  for (const [key, [name, schema]] of Object.entries(VARS)) {
    const raw = (env as unknown as Record<string, string | undefined>)[name];
    const parsed = schema.safeParse(raw);
    if (!parsed.success) {
      throw new ApiError(500, "config_invalid", `${name}: ${parsed.error.issues[0]?.message ?? "missing"}`);
    }
    out[key] = parsed.data;
  }
  return out as RemoteConfig;
}
