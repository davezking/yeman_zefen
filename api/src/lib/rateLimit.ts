// Rate limits on the player API (/v1). Why two mechanisms: see docs/ops.md "Rate limiting".
//
// - Per IP, 300 requests a minute across /v1: Cloudflare's Workers Rate Limiting binding
//   (IP_LIMITER). It is counted at the edge, costs no D1 query, and exists on every plan. Its
//   period can only be 10 or 60 seconds, so it cannot do the per-hour player limits.
// - Per player (UID): a token bucket in D1, one statement per limited request. The bucket's size is
//   the burst (an offline player syncing queued sessions), its refill rate is the hourly limit.
//
// A refused request is 429 `rate_limited` with `Retry-After` (seconds), which the app's sync loop
// waits out (app/lib/features/game/data/session_sync.dart).
import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../env";
import { ApiError } from "./errors";

/** Requests per minute per IP across /v1. Mirrors `limit` of IP_LIMITER in wrangler.toml. */
export const IP_LIMIT_PER_MINUTE = 300;
/** The IP binding's period (wrangler.toml); the best Retry-After it lets us give. */
const IP_PERIOD_S = 60;

export type BucketRule = {
  /** The bucket's size: how many requests may arrive at once. */
  burst: number;
  /** The long-run limit: tokens added per hour. */
  perHour: number;
};

/** Per-player limits. Clip reports (10 a day) have their own counter in routes/v1/reports.ts. */
export const UID_RULES = {
  sessions: { burst: 20, perHour: 60 },
  merge: { burst: 5, perHour: 5 },
  me: { burst: 30, perHour: 30 },
} as const satisfies Record<string, BucketRule>;

export type UidRule = keyof typeof UID_RULES;

const HOUR_MS = 3_600_000;

/**
 * Takes one token from `key`'s bucket, creating it full. One atomic statement: the refill, the
 * spend and the verdict happen together, so two requests at once cannot both take the last token.
 * ?1 key, ?2 now, ?3 burst, ?4 tokens added per ms.
 */
const TAKE_SQL = `
  INSERT INTO rate_limits (key, tokens, updated_at, allowed) VALUES (?1, ?3 - 1, ?2, 1)
  ON CONFLICT (key) DO UPDATE SET
    allowed = (MIN(?3, tokens + MAX(?2 - updated_at, 0) * ?4) >= 1),
    tokens = MIN(?3, tokens + MAX(?2 - updated_at, 0) * ?4)
             - (MIN(?3, tokens + MAX(?2 - updated_at, 0) * ?4) >= 1),
    updated_at = MAX(?2, updated_at)
  RETURNING allowed, tokens`;

export type TakeResult = { allowed: true } | { allowed: false; retryAfterS: number };

export async function takeToken(db: D1Database, key: string, rule: BucketRule, now: number): Promise<TakeResult> {
  const perMs = rule.perHour / HOUR_MS;
  const row = await db
    .prepare(TAKE_SQL)
    .bind(key, now, rule.burst, perMs)
    .first<{ allowed: number; tokens: number }>();
  if (row === null || row.allowed === 1) return { allowed: true };
  return { allowed: false, retryAfterS: Math.max(1, Math.ceil(((1 - row.tokens) / perMs) / 1000)) };
}

function tooMany(c: Parameters<MiddlewareHandler<AppEnv>>[0], retryAfterS: number, what: string): never {
  c.header("Retry-After", String(retryAfterS));
  throw new ApiError(429, "rate_limited", `Too many ${what}. Try again in ${retryAfterS} seconds.`);
}

/** Per-IP limit. Skipped when the binding is not configured (local dev) or the IP is unknown. */
export function ipRateLimit(): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const limiter = c.env.IP_LIMITER;
    const ip = c.req.header("cf-connecting-ip");
    if (limiter && ip) {
      const { success } = await limiter.limit({ key: ip });
      if (!success) tooMany(c, IP_PERIOD_S, "requests");
    }
    await next();
  };
}

/**
 * Per-player limit for the routes selected by `applies`. Runs after authentication (it needs the
 * uid), and before the body is read, so a refused request costs one D1 statement and nothing else.
 */
export function uidRateLimit(rule: UidRule, applies: (method: string) => boolean = () => true): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const user = c.get("user");
    if (user && applies(c.req.method)) {
      const verdict = await takeToken(c.env.DB, `${rule}:${user.uid}`, UID_RULES[rule], Date.now());
      if (!verdict.allowed) tooMany(c, verdict.retryAfterS, "requests");
    }
    await next();
  };
}
