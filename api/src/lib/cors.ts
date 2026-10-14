// CORS for the admin SPA. The SPA is served from its own origin (admin.<domain>, or the
// Vite dev server locally) and calls /admin/* with `credentials: 'include'`, so only the
// one origin in ADMIN_ORIGIN is allowed to read responses. Every other origin gets no
// CORS headers, which the browser treats as a failed cross-origin request.
import { cors } from "hono/cors";
import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../env";

export function adminCors(): MiddlewareHandler<AppEnv> {
  return cors({
    origin: (origin, c) => (origin === c.env.ADMIN_ORIGIN ? origin : null),
    allowMethods: ["GET", "POST", "PATCH", "PUT", "DELETE"],
    allowHeaders: ["Content-Type"],
    // Lets the SPA show the request id in error notifications, to match them with Worker logs.
    exposeHeaders: ["X-Request-Id"],
    credentials: true,
    maxAge: 600,
  });
}
