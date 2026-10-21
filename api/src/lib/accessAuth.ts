// The two admin-boundary middlewares: admins (requireAdmin) and the ingest jobs (requireService).
// Spec: docs/architecture.md §6 and docs/phase-1-sprint-1-prompts.md.
//
// How an admin proves who they are depends on ADMIN_LOGIN (docs/ops.md, "Admin authentication"):
//   - "access" (the default): every /admin/* route sits behind Cloudflare Access, which injects a
//     `Cf-Access-Jwt-Assertion` header. We still verify that JWT ourselves (defense in depth)
//     against the team JWKS. This needs the admin site and the API on hostnames of one domain.
//   - "firebase": the admin site signs in with Google through Firebase Auth and sends the ID
//     token as `Authorization: Bearer`. No cookie is involved, so it works when the admin site
//     and the API are on unrelated hostnames (pages.dev and workers.dev).
// Either way the email must be in `admin_users`. In "firebase" mode the Access header is ignored,
// and in "access" mode the Bearer token is: one mode at a time, never a fall-through.
//
// The ingest jobs authenticate with the Access service token (`common_name`), or with the shared
// secret INGEST_TOKEN as a Bearer token where Access is not in front of the API.
import { eq } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from "jose";
import { db } from "../db/client";
import { ADMIN_ROLES, adminUsers } from "../db/schema";
import type { AppEnv, Bindings } from "../env";
import { ApiError } from "./errors";
import { bearerToken, KeysUnavailableError, verifyFirebaseIdToken } from "./firebaseAuth";

export const ACCESS_HEADER = "cf-access-jwt-assertion";

export type AdminRole = (typeof ADMIN_ROLES)[number];

/** How admins sign in. Anything but "firebase" is "access", so a typo keeps the stricter default. */
export type AdminLogin = "access" | "firebase";
export const adminLogin = (env: Pick<Bindings, "ADMIN_LOGIN">): AdminLogin => (env.ADMIN_LOGIN === "firebase" ? "firebase" : "access");

/** The sign-in provider an admin's Firebase token must come from. */
export const ADMIN_FIREBASE_PROVIDER = "google.com";
/** INGEST_TOKEN shorter than this is treated as not set: a short shared secret can be guessed. */
export const MIN_INGEST_TOKEN_LENGTH = 32;

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
 * The verified Google email of a Firebase ID token sent as `Authorization: Bearer`. 401 for a missing or
 * bad token, 503 when Google's keys cannot be fetched, 403 for a token not from a Google sign-in or
 * without a verified email.
 */
async function firebaseAdminEmail(env: Bindings, token: string, requestId: string | undefined): Promise<string> {
  let user;
  try {
    user = await verifyFirebaseIdToken(token, env.FIREBASE_PROJECT_ID);
  } catch (err) {
    if (err instanceof KeysUnavailableError) {
      console.error(JSON.stringify({ requestId, event: "admin_auth_keys_unavailable", reason: err.message }));
      throw new ApiError(503, "auth_unavailable", "Authentication is temporarily unavailable");
    }
    console.warn(JSON.stringify({ requestId, event: "admin_auth_failed", reason: err instanceof Error ? err.message : String(err) }));
    throw new ApiError(401, "unauthorized", "Invalid sign-in token");
  }
  if (user.provider !== ADMIN_FIREBASE_PROVIDER || !user.email) {
    throw new ApiError(403, "forbidden", "Sign in with a Google account that is an admin");
  }
  return user.email;
}

/**
 * Require a human admin. The verified email must exist in `admin_users` with one
 * of `roles` (any role by default). Sets `{ email, role }` on the context.
 *
 * Dev convenience: when `ENV=dev` AND `DEV_ADMIN_EMAIL` is set, a request with no
 * token is treated as that email (still subject to the admin_users check).
 * With `DEV_ADMIN_EMAIL` unset, a missing token is 401 even in dev.
 */
export function requireAdmin(roles: readonly AdminRole[] = ADMIN_ROLES): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const firebase = adminLogin(c.env) === "firebase";
    const token = firebase ? bearerToken(c.req.header("authorization")) : c.req.header(ACCESS_HEADER);
    let email: string | undefined;
    if (token) {
      email = firebase ? await firebaseAdminEmail(c.env, token, c.get("requestId")) : (await verifyHeaderOrThrow(c.env, token)).email;
    } else if (c.env.ENV === "dev" && c.env.DEV_ADMIN_EMAIL) {
      email = c.env.DEV_ADMIN_EMAIL;
    } else {
      throw new ApiError(401, "unauthorized", firebase ? "Missing sign-in token" : "Missing Access token");
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

/** Compares two secrets in constant time (as digests, so their lengths do not leak either). */
async function sameSecret(given: string, expected: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([crypto.subtle.digest("SHA-256", enc.encode(given)), crypto.subtle.digest("SHA-256", enc.encode(expected))]);
  return crypto.subtle.timingSafeEqual(a, b);
}

/**
 * Require the ingest jobs. Either the shared secret INGEST_TOKEN as `Authorization: Bearer` (when it is
 * set, at least MIN_INGEST_TOKEN_LENGTH characters), or the Access service token: the verified JWT's
 * `common_name` must equal `INGEST_SERVICE_CLIENT_ID`. Human (email) tokens never satisfy this.
 */
export function requireService(): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const expectedSecret = c.env.INGEST_TOKEN ?? "";
    const bearer = bearerToken(c.req.header("authorization"));
    if (bearer && expectedSecret.length >= MIN_INGEST_TOKEN_LENGTH) {
      if (!(await sameSecret(bearer, expectedSecret))) throw new ApiError(401, "unauthorized", "Invalid ingest token");
      c.set("service", { clientId: "ingest-token" });
      await next();
      return;
    }
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
