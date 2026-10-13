// Cloudflare Access JWT verification and the two admin-boundary middlewares.
// Spec: docs/architecture.md §6 and docs/phase-1-sprint-1-prompts.md.
//
// Every /admin/* route sits behind Cloudflare Access, which injects a
// `Cf-Access-Jwt-Assertion` header. We still verify that JWT ourselves
// (defense in depth) against the team JWKS, then authorize:
//   - humans by email in `admin_users` (requireAdmin),
//   - the ingest service token by `common_name` (requireService).
// We never trust any other header, and never fall through to one.
import { eq } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from "jose";
import { db } from "../db/client";
import { ADMIN_ROLES, adminUsers } from "../db/schema";
import type { AppEnv, Bindings } from "../env";
import { ApiError } from "./errors";

export const ACCESS_HEADER = "cf-access-jwt-assertion";

export type AdminRole = (typeof ADMIN_ROLES)[number];

export interface AccessClaims extends JWTPayload {
  /** Present on human (identity) tokens. */
  email?: string;
  /** Present on service-token JWTs instead of `email`. */
  common_name?: string;
}

// One remote JWKS per team domain, cached at module scope so the certs are
// fetched once and reused across requests (jose caches internally too).
const jwksByDomain = new Map<string, JWTVerifyGetKey>();

// Test-only seam: when set, used instead of the remote JWKS so tests can sign
// with a local key pair. Never set in production code paths.
let testKeyResolver: JWTVerifyGetKey | null = null;

/** Test-only. Pass a `createLocalJWKSet(...)` resolver, or null to restore remote behavior. */
export function __setTestKeyResolver(resolver: JWTVerifyGetKey | null): void {
  testKeyResolver = resolver;
}

function keyResolver(teamDomain: string): JWTVerifyGetKey {
  if (testKeyResolver) return testKeyResolver;
  let resolver = jwksByDomain.get(teamDomain);
  if (!resolver) {
    resolver = createRemoteJWKSet(new URL(`${teamDomain}/cdn-cgi/access/certs`));
    jwksByDomain.set(teamDomain, resolver);
  }
  return resolver;
}

/**
 * Verify a Cloudflare Access JWT. Checks the signature against the team JWKS,
 * `iss === teamDomain`, that `aud` includes `expectedAud`, and `exp` (jose does
 * exp/nbf automatically). Throws on any failure — callers turn that into 401.
 */
export async function verifyAccessJwt(
  token: string,
  teamDomain: string,
  expectedAud: string,
): Promise<AccessClaims> {
  const { payload } = await jwtVerify(token, keyResolver(teamDomain), {
    issuer: teamDomain,
    audience: expectedAud,
  });
  return payload as AccessClaims;
}

async function verifyHeaderOrThrow(env: Bindings, token: string): Promise<AccessClaims> {
  try {
    return await verifyAccessJwt(token, env.ACCESS_TEAM_DOMAIN, env.ACCESS_AUD);
  } catch {
    // Bad signature, wrong aud/iss, expired, or JWKS unreachable — all 401,
    // never 500, and never a fallback to trusting the request.
    throw new ApiError(401, "unauthorized", "Invalid Access token");
  }
}

/**
 * Require a human admin. The verified email must exist in `admin_users` with one
 * of `roles` (any role by default). Sets `{ email, role }` on the context.
 *
 * Dev convenience: when `ENV=dev` AND `DEV_ADMIN_EMAIL` is set, a request with no
 * Access header is treated as that email (still subject to the admin_users check).
 * With `DEV_ADMIN_EMAIL` unset, a missing header is 401 even in dev.
 */
export function requireAdmin(roles: readonly AdminRole[] = ADMIN_ROLES): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const token = c.req.header(ACCESS_HEADER);
    let email: string | undefined;
    if (token) {
      email = (await verifyHeaderOrThrow(c.env, token)).email;
    } else if (c.env.ENV === "dev" && c.env.DEV_ADMIN_EMAIL) {
      email = c.env.DEV_ADMIN_EMAIL;
    } else {
      throw new ApiError(401, "unauthorized", "Missing Access token");
    }
    if (!email) throw new ApiError(403, "forbidden", "Not an authorized admin");
    const row = await db(c.env).select().from(adminUsers).where(eq(adminUsers.email, email)).get();
    if (!row || !roles.includes(row.role)) {
      throw new ApiError(403, "forbidden", "Not an authorized admin");
    }
    c.set("admin", { email: row.email, role: row.role });
    await next();
  };
}

/**
 * Narrow an already-authenticated admin route to specific roles. Must run after
 * `requireAdmin()` (which sets the context); with no admin on the context it is a 401,
 * so it can never grant access on its own.
 */
export function requireRole(...roles: readonly AdminRole[]): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const admin = c.get("admin");
    if (!admin) throw new ApiError(401, "unauthorized", "Not authenticated");
    if (!roles.includes(admin.role)) {
      throw new ApiError(403, "forbidden", `Requires role: ${roles.join(" or ")}`);
    }
    await next();
  };
}

/**
 * Require the ingest service token. The verified JWT's `common_name` must equal
 * `INGEST_SERVICE_CLIENT_ID`. Human (email) tokens never satisfy this.
 */
export function requireService(): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const token = c.req.header(ACCESS_HEADER);
    if (!token) throw new ApiError(401, "unauthorized", "Missing Access token");
    const claims = await verifyHeaderOrThrow(c.env, token);
    const expected = c.env.INGEST_SERVICE_CLIENT_ID;
    if (!expected || !claims.common_name || claims.common_name !== expected) {
      throw new ApiError(403, "forbidden", "Not an authorized service token");
    }
    c.set("service", { clientId: claims.common_name });
    await next();
  };
}
