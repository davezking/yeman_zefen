// Firebase ID token verification and the player-boundary middleware.
// Spec: docs/architecture.md §6 and docs/phase-3-sprint-1-prompts.md.
//
// Every non-public /v1 request carries `Authorization: Bearer <Firebase ID token>`.
// The token is an RS256 JWT signed by Google's securetoken service account.
// We check the signature against Google's published JWKS (cached per isolate),
// then iss, aud, exp, iat, auth_time and sub, as Firebase's docs require for
// verifying ID tokens with a third-party JWT library.
//
// Failures are 401 with one generic message; the reason is logged server-side
// only. A failure to *get the keys* is 503, so an outage at Google is not
// reported to the app as "your token is bad" (which would make it sign out).
import type { MiddlewareHandler } from "hono";
import {
  createRemoteJWKSet,
  customFetch,
  errors,
  jwtVerify,
  type FetchImplementation,
  type JWTPayload,
  type JWTVerifyGetKey,
} from "jose";
import type { AppEnv } from "../env";
import { ApiError } from "./errors";

export const FIREBASE_JWKS_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

/** Seconds of clock skew allowed on exp, iat and auth_time. */
const CLOCK_TOLERANCE_S = 60;
/** The placeholder user that owns sessions of deleted accounts (migration 0006). No real player may have this uid. */
export const DELETED_USER_ID = "deleted";
/** Firebase UIDs are at most 128 characters. */
const MAX_UID_LENGTH = 128;
/** Firebase ID tokens are ~1 KB; anything far larger is not one, so skip the crypto. */
const MAX_TOKEN_LENGTH = 8192;

export type PlayerUser = {
  uid: string;
  isAnonymous: boolean;
  /** `firebase.sign_in_provider`, e.g. "anonymous", "google.com", "password", "apple.com". */
  provider: string;
  /** Present only when the token says the email is verified. */
  email?: string;
};

export interface FirebaseClaims extends JWTPayload {
  auth_time?: unknown;
  email?: unknown;
  email_verified?: unknown;
  firebase?: { sign_in_provider?: unknown };
}

/** The token is not acceptable. Maps to 401. */
export class InvalidTokenError extends Error {
  override name = "InvalidTokenError";
}
/** The signing keys could not be fetched or used. Maps to 503. */
export class KeysUnavailableError extends Error {
  override name = "KeysUnavailableError";
}

// One remote JWKS per isolate, created on first use. jose caches the fetched
// keys inside it and refetches on an unknown `kid` (at most every 30 s), which
// is how Google key rotation is picked up. A stale cache is refetched before
// use and a failed refetch is a 503, so keep the max age long: Google publishes
// new keys hours before signing with them and serves the JWKS with a
// multi-hour max-age.
const JWKS_CACHE_MAX_AGE_MS = 60 * 60 * 1000;
let jwks: JWTVerifyGetKey | null = null;
let jwksFetch: FetchImplementation | undefined;

/**
 * Test-only. Replace the fetch the JWKS uses (or pass null for the real one).
 * Always drops the cached key set, so the next verification fetches again.
 */
export function __setFirebaseJwksFetch(fetchImpl: FetchImplementation | null): void {
  jwksFetch = fetchImpl ?? undefined;
  jwks = null;
}

function remoteKeys(): JWTVerifyGetKey {
  if (!jwks) {
    jwks = createRemoteJWKSet(new URL(FIREBASE_JWKS_URL), {
      cacheMaxAge: JWKS_CACHE_MAX_AGE_MS,
      ...(jwksFetch ? { [customFetch]: jwksFetch } : {}),
    });
  }
  return jwks;
}

// Wrap the resolver so key-source failures (network, non-200, bad JSON,
// timeout) are told apart from token failures. "No key for this kid" is the
// token's fault: jose has already refetched once before reporting it.
const keyResolver: JWTVerifyGetKey = async (header, token) => {
  // `algorithms` already rejects other algs before we get here; this keeps a
  // malformed header from ever being reported as a key outage (503).
  if (header.alg !== "RS256" || typeof header.kid !== "string" || header.kid.length === 0) {
    throw new InvalidTokenError("unexpected alg or missing kid");
  }
  try {
    return await remoteKeys()(header, token);
  } catch (err) {
    if (err instanceof errors.JWKSNoMatchingKey || err instanceof errors.JWKSMultipleMatchingKeys) throw err;
    throw new KeysUnavailableError(`JWKS unavailable: ${describe(err)}`, { cause: err });
  }
};

function describe(err: unknown): string {
  if (err instanceof errors.JOSEError) return `${err.code}: ${err.message}`;
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}

/**
 * Verify a Firebase ID token for `projectId` and return the player it names.
 * Throws `InvalidTokenError` for a bad token and `KeysUnavailableError` when
 * Google's keys cannot be fetched. `allowExpiredUpToS` accepts an expired token
 * issued at most that many seconds ago (POST /v1/me/merge only).
 */
export async function verifyFirebaseIdToken(
  token: string,
  projectId: string,
  { allowExpiredUpToS }: { allowExpiredUpToS?: number } = {},
): Promise<PlayerUser> {
  if (!projectId) throw new KeysUnavailableError("FIREBASE_PROJECT_ID is not configured");
  if (token.length > MAX_TOKEN_LENGTH) throw new InvalidTokenError("token too long");

  let payload: FirebaseClaims;
  try {
    ({ payload } = await jwtVerify<FirebaseClaims>(token, keyResolver, {
      algorithms: ["RS256"],
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      // An expired token is still accepted when the caller allows it: the signature, issuer and
      // audience are checked as usual, and its age is checked below. (Not jose's maxTokenAge,
      // which would add this same tolerance to the age.)
      clockTolerance: allowExpiredUpToS ?? CLOCK_TOLERANCE_S,
      requiredClaims: ["exp", "iat", "sub", "auth_time"],
    }));
  } catch (err) {
    if (err instanceof KeysUnavailableError || err instanceof InvalidTokenError) throw err;
    throw new InvalidTokenError(describe(err), { cause: err });
  }

  // jose checks exp, and iat only for type; Firebase also wants iat and
  // auth_time in the past.
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.iat !== "number" || payload.iat > now + CLOCK_TOLERANCE_S) {
    throw new InvalidTokenError("iat is not in the past");
  }
  if (allowExpiredUpToS !== undefined && now - payload.iat > allowExpiredUpToS) {
    throw new InvalidTokenError("token is too old");
  }
  const authTime = payload.auth_time;
  if (typeof authTime !== "number" || !Number.isFinite(authTime) || authTime > now + CLOCK_TOLERANCE_S) {
    throw new InvalidTokenError("auth_time is not in the past");
  }
  const uid = payload.sub;
  if (typeof uid !== "string" || uid.length === 0 || uid.length > MAX_UID_LENGTH) {
    throw new InvalidTokenError("sub is empty or too long");
  }
  if (uid === DELETED_USER_ID) throw new InvalidTokenError("sub is reserved");
  const provider = payload.firebase?.sign_in_provider;
  if (typeof provider !== "string" || provider.length === 0) {
    throw new InvalidTokenError("firebase.sign_in_provider is missing");
  }

  const user: PlayerUser = { uid, isAnonymous: provider === "anonymous", provider };
  // Only a verified email: the password provider issues tokens for addresses
  // nobody has proven they own.
  if (typeof payload.email === "string" && payload.email.length > 0 && payload.email_verified === true) {
    user.email = payload.email;
  }
  return user;
}

export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer[ ]+([^\s]+)[ ]*$/i.exec(header);
  return match ? match[1]! : null;
}

function logAuthFailure(requestId: string | undefined, reason: string): void {
  console.warn(JSON.stringify({ requestId, event: "player_auth_failed", reason }));
}

/**
 * Require a Firebase-authenticated player. Sets `{ uid, isAnonymous, provider, email? }`
 * on `c.var.user`. 401 for a missing or invalid token, 503 when Google's keys are
 * unreachable, and 403 for an anonymous user when `allowAnonymous` is false.
 *
 * If an earlier `requireUser()` already verified this request, the token is not
 * verified again; only the anonymous check runs.
 */
export function requireUser({ allowAnonymous = true }: { allowAnonymous?: boolean } = {}): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    let user = c.get("user");
    if (!user) {
      const token = bearerToken(c.req.header("authorization"));
      if (!token) {
        logAuthFailure(c.get("requestId"), "missing bearer token");
        throw new ApiError(401, "unauthorized", "Authentication required");
      }
      try {
        user = await verifyFirebaseIdToken(token, c.env.FIREBASE_PROJECT_ID);
      } catch (err) {
        if (err instanceof KeysUnavailableError) {
          console.error(JSON.stringify({ requestId: c.get("requestId"), event: "player_auth_keys_unavailable", reason: err.message }));
          throw new ApiError(503, "auth_unavailable", "Authentication is temporarily unavailable");
        }
        logAuthFailure(c.get("requestId"), err instanceof Error ? err.message : String(err));
        throw new ApiError(401, "unauthorized", "Authentication required");
      }
      c.set("user", user);
    }
    if (!allowAnonymous && user.isAnonymous) {
      throw new ApiError(403, "registration_required", "This requires a registered account");
    }
    await next();
  };
}
