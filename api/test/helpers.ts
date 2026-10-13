import { env, exports } from "cloudflare:workers";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { db } from "../src/db/client";
import { adminUsers, artists, clips, tracks } from "../src/db/schema";
import { __setTestKeyResolver, ACCESS_HEADER } from "../src/lib/accessAuth";

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
