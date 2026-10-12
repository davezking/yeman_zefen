import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../env";

/** Reuses an incoming `X-Request-Id` (or Cloudflare's `cf-ray`), else generates one, and echoes it back. */
export const requestId = (): MiddlewareHandler<AppEnv> => async (c, next) => {
  const incoming = c.req.header("x-request-id");
  const id =
    incoming && /^[\w-]{1,128}$/.test(incoming) ? incoming : (c.req.header("cf-ray") ?? crypto.randomUUID());
  c.set("requestId", id);
  await next();
  c.header("X-Request-Id", id);
};
