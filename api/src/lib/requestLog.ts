import type { MiddlewareHandler } from "hono";
import { routePath } from "hono/route";
import type { AppEnv } from "../env";
import { requestCountry } from "./country";

/** SHA-256 of the UID as hex, truncated to 16 characters. The UID itself is never logged. */
export async function hashUid(uid: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(uid));
  return [...new Uint8Array(digest)]
    .slice(0, 8)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Writes one JSON line per request (Workers Logs picks up console output). Fields: requestId, route
 * (the endpoint's pattern, so IDs in paths stay out, even when a middleware rejected the request),
 * status, latencyMs, uidHash, country, and the error code when the request failed. Never tokens,
 * bodies, or emails.
 */
export const requestLog = (): MiddlewareHandler<AppEnv> => async (c, next) => {
  const startedAt = Date.now();
  await next();
  const user = c.get("user");
  const line = {
    requestId: c.get("requestId"),
    route: routePath(c, -1),
    status: c.res.status,
    latencyMs: Date.now() - startedAt,
    uidHash: user ? await hashUid(user.uid) : undefined,
    country: requestCountry(c.req.raw) ?? undefined,
    errorCode: c.get("errorCode"),
  };
  console.log(JSON.stringify(line));
};
