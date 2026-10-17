import { env, exports } from "cloudflare:workers";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { db } from "../src/db/client";
import { adminUsers, artists, clips, ingestJobs, tracks } from "../src/db/schema";
import { __setTestKeyResolver, ACCESS_HEADER } from "../src/lib/accessAuth";
import { __setFirebaseJwksFetch } from "../src/lib/firebaseAuth";

export const TEAM = "https://yz.cloudflareaccess.com";
export const AUD = "test-access-aud";
export const SERVICE_ID = "test-service.client";

let privateKey: CryptoKey;

type Claims = { email?: string; common_name?: string };
type SignOpts = { iss?: string; aud?: string; expiresIn?: string | number };

/** Generate a key pair and make the Worker trust it (test-only JWKS seam). */
export async function installTestJwks(): Promise<void> {
  const pair = await generateKeyPair("RS256", { extractable: true });
  privateKey = pair.privateKey;
  const jwk = await exportJWK(pair.publicKey);
  jwk.kid = "test-key";
  jwk.alg = "RS256";
  __setTestKeyResolver(createLocalJWKSet({ keys: [jwk] }));
}

export function removeTestJwks(): void {
  __setTestKeyResolver(null);
}

export async function signAccessJwt(claims: Claims, opts: SignOpts = {}): Promise<string> {
  const jwt = new SignJWT({ ...claims })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuedAt(Math.floor(Date.now() / 1000))
    .setIssuer(opts.iss ?? TEAM)
    .setAudience(opts.aud ?? AUD);
  jwt.setExpirationTime(opts.expiresIn ?? "1h");
  return jwt.sign(privateKey);
}

export async function seedAdmins(): Promise<void> {
  await db(env)
    .insert(adminUsers)
    .values([
      { email: "admin@yz.test", role: "admin", createdAt: Date.now() },
      { email: "editor@yz.test", role: "editor", createdAt: Date.now() },
    ])
    .onConflictDoNothing();
}

export async function rawRequest(path: string, init: RequestInit & { jwt?: string } = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (init.jwt) headers.set(ACCESS_HEADER, init.jwt);
  return exports.default.fetch(new Request(`https://api.test${path}`, { ...init, headers }));
}

/** Call the Worker as a signed-in admin or editor. */
export async function api(
  path: string,
  opts: { method?: string; body?: unknown; as?: "admin" | "editor" } = {},
): Promise<Response> {
  const jwt = await signAccessJwt({ email: `${opts.as ?? "admin"}@yz.test` });
  return rawRequest(path, {
    method: opts.method ?? (opts.body === undefined ? "GET" : "POST"),
    jwt,
    headers: opts.body === undefined ? undefined : { "content-type": "application/json" },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
}

/** Call the Worker as the ingest service token (GitHub Actions). */
export async function svc(path: string, opts: { method?: string; body?: unknown } = {}): Promise<Response> {
  const jwt = await signAccessJwt({ common_name: SERVICE_ID });
  return rawRequest(path, {
    method: opts.method ?? (opts.body === undefined ? "GET" : "POST"),
    jwt,
    headers: opts.body === undefined ? undefined : { "content-type": "application/json" },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
}

export async function makeJob(
  kind: "scrape" | "cut" | "recut" = "scrape",
  status: "queued" | "running" | "succeeded" | "failed" = "running",
) {
  const [row] = await db(env).insert(ingestJobs).values({ kind, status }).returning();
  return row!;
}

const now = 1_760_000_000_000;

export async function makeArtist(nameAm: string, nameLatin: string | null = null) {
  const [row] = await db(env).insert(artists).values({ nameAm, nameLatin, createdAt: now, updatedAt: now }).returning();
  return row!;
}

export async function makeTrack(
  artistId: number,
  fields: Partial<typeof tracks.$inferInsert> = {},
) {
  const [row] = await db(env)
    .insert(tracks)
    .values({ artistId, createdAt: now, updatedAt: now, ...fields })
    .returning();
  return row!;
}

export async function makeClip(trackId: number, type: "intro" | "middle", status: "pending" | "ready" | "failed" = "ready") {
  const [row] = await db(env)
    .insert(clips)
    .values({ trackId, type, startMs: 0, status, r2Key: `clips/${trackId}-${type}.mp3` })
    .returning();
  return row!;
}

/** Tests share one D1 per file (no per-test rollback), so wipe catalog rows between tests. Seed and admin rows stay. */
export async function resetCatalog(): Promise<void> {
  await env.DB.batch(
    [
      "review_items",
      "ingest_jobs",
      "pack_tracks",
      "pack_versions",
      "packs",
      "clips",
      "track_genres",
      "tracks",
      "artist_aliases",
      "artists",
    ].map((t) => env.DB.prepare(`DELETE FROM ${t}`)),
  );
}

/**
 * Wraps a D1 binding and counts every statement that reaches D1. Cloudflare's Free plan caps
 * queries per Worker invocation (50), and each statement inside a batch() counts.
 */
export function countingDb(real: D1Database) {
  // `writes` counts statements that write (INSERT/UPDATE/DELETE/REPLACE), a subset of `queries`.
  const counter = { queries: 0, writes: 0 };
  const isWrite = (sql: string) => /^\s*(INSERT|UPDATE|DELETE|REPLACE)\b/i.test(sql);
  class CountedStatement {
    constructor(
      readonly inner: D1PreparedStatement,
      readonly sql: string,
    ) {}
    bind(...values: unknown[]) {
      return new CountedStatement(this.inner.bind(...values), this.sql);
    }
    run() {
      this.count();
      return this.inner.run();
    }
    all() {
      this.count();
      return this.inner.all();
    }
    first(column?: string) {
      this.count();
      return column === undefined ? this.inner.first() : this.inner.first(column);
    }
    raw(options?: { columnNames?: boolean }) {
      this.count();
      return this.inner.raw(options as { columnNames: true });
    }
    count() {
      counter.queries++;
      if (isWrite(this.sql)) counter.writes++;
    }
  }
  const wrapped = {
    prepare: (query: string) => new CountedStatement(real.prepare(query), query),
    batch: (statements: CountedStatement[]) => {
      for (const s of statements) s.count();
      return real.batch(statements.map((s) => s.inner));
    },
  } as unknown as D1Database;
  return { db: wrapped, counter };
}

/** Call the app directly with a counting DB (as the ingest service token) and report how many D1 queries it used. */
export async function svcWithQueryCount(
  path: string,
  body?: unknown,
): Promise<{ response: Response; queries: number }> {
  const { default: app } = await import("../src/index");
  const { db, counter } = countingDb(env.DB);
  const jwt = await signAccessJwt({ common_name: SERVICE_ID });
  const response = await app.fetch(
    new Request(`https://api.test${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: body === undefined ? { [ACCESS_HEADER]: jwt } : { "content-type": "application/json", [ACCESS_HEADER]: jwt },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    { ...env, DB: db },
  );
  return { response, queries: counter.queries };
}

/** Call the app directly with a counting DB as a signed-in admin, and report how many D1 queries it used. */
export async function adminWithQueryCount(
  path: string,
  opts: { method?: string; body?: unknown } = {},
): Promise<{ response: Response; queries: number }> {
  const { default: app } = await import("../src/index");
  const { db, counter } = countingDb(env.DB);
  const jwt = await signAccessJwt({ email: "admin@yz.test" });
  const response = await app.fetch(
    new Request(`https://api.test${path}`, {
      method: opts.method ?? (opts.body === undefined ? "GET" : "POST"),
      headers: opts.body === undefined ? { [ACCESS_HEADER]: jwt } : { "content-type": "application/json", [ACCESS_HEADER]: jwt },
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    }),
    { ...env, DB: db },
  );
  return { response, queries: counter.queries };
}

// ---- Player (Firebase) auth ----

let firebaseKey: CryptoKey;

/** Make the Worker trust a freshly generated key for Firebase ID tokens (test-only JWKS fetch seam). */
export async function installFirebaseJwks(): Promise<void> {
  const pair = await generateKeyPair("RS256", { extractable: true });
  firebaseKey = pair.privateKey;
  const jwk = { ...(await exportJWK(pair.publicKey)), kid: "fb-test-key", alg: "RS256", use: "sig" };
  __setFirebaseJwksFetch(async () => Response.json({ keys: [jwk] }));
}

export function removeFirebaseJwks(): void {
  __setFirebaseJwksFetch(null);
}

/**
 * A valid Firebase ID token for `uid` (anonymous unless `provider` says otherwise). `ageS` backdates
 * it (a token is good for an hour, so over 3600 it is expired); `key` signs it with another key.
 */
export async function signFirebaseToken(
  uid: string,
  opts: { provider?: string; ageS?: number; key?: CryptoKey } = {},
): Promise<string> {
  const projectId = (env as { FIREBASE_PROJECT_ID: string }).FIREBASE_PROJECT_ID;
  const iat = Math.floor(Date.now() / 1000) - (opts.ageS ?? 10);
  return new SignJWT({ auth_time: iat, firebase: { sign_in_provider: opts.provider ?? "anonymous", identities: {} } })
    .setProtectedHeader({ alg: "RS256", kid: "fb-test-key", typ: "JWT" })
    .setIssuer(`https://securetoken.google.com/${projectId}`)
    .setAudience(projectId)
    .setSubject(uid)
    .setIssuedAt(iat)
    .setExpirationTime(iat + 3600)
    .sign(opts.key ?? firebaseKey);
}

/** Call the Worker as a signed-in player. */
export async function player(
  uid: string,
  path: string,
  opts: { method?: string; body?: unknown; provider?: string; cf?: { country: string } } = {},
): Promise<Response> {
  const token = await signFirebaseToken(uid, { provider: opts.provider });
  const headers: Record<string, string> = { authorization: `Bearer ${token}` };
  if (opts.body !== undefined) headers["content-type"] = "application/json";
  return exports.default.fetch(
    new Request(`https://api.test${path}`, {
      method: opts.method ?? (opts.body === undefined ? "GET" : "PUT"),
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      // Cloudflare sets request.cf at the edge; tests inject it.
      ...(opts.cf ? { cf: opts.cf } : {}),
    }),
  );
}
