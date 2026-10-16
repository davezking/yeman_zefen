import { env, exports } from "cloudflare:workers";
import { Hono } from "hono";
import { base64url, exportJWK, exportSPKI, generateKeyPair, SignJWT, type JWK } from "jose";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type { AppEnv } from "../src/env";
import { onError } from "../src/lib/errors";
import { __setFirebaseJwksFetch, FIREBASE_JWKS_URL, requireUser } from "../src/lib/firebaseAuth";

const PROJECT = (env as { FIREBASE_PROJECT_ID: string }).FIREBASE_PROJECT_ID;
const ISS = `https://securetoken.google.com/${PROJECT}`;
const KID = "fb-test-key";

let privateKey: CryptoKey;
let publicJwk: JWK;
let publicPem: string;

/** A fetch mock serving the test JWKS, counting calls. Set `fail` to make it return 500. */
const jwksServer = { calls: 0, fail: false, urls: [] as string[] };
async function fakeJwksFetch(url: string): Promise<Response> {
  jwksServer.calls++;
  jwksServer.urls.push(url);
  if (jwksServer.fail) return new Response("upstream down", { status: 500 });
  return Response.json({ keys: [publicJwk] });
}

beforeAll(async () => {
  const pair = await generateKeyPair("RS256", { extractable: true });
  privateKey = pair.privateKey;
  publicJwk = { ...(await exportJWK(pair.publicKey)), kid: KID, alg: "RS256", use: "sig" };
  publicPem = await exportSPKI(pair.publicKey);
});

beforeEach(() => {
  jwksServer.calls = 0;
  jwksServer.fail = false;
  jwksServer.urls = [];
  __setFirebaseJwksFetch(fakeJwksFetch);
});

afterAll(() => __setFirebaseJwksFetch(null));

type Opts = {
  sub?: string | null;
  aud?: string;
  iss?: string;
  provider?: string;
  email?: string;
  emailVerified?: boolean;
  exp?: number;
  iat?: number;
  authTime?: number | null;
};

async function firebaseToken(opts: Opts = {}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claims: Record<string, unknown> = {
    firebase: { sign_in_provider: opts.provider ?? "anonymous", identities: {} },
  };
  if (opts.authTime !== null) claims.auth_time = opts.authTime ?? now - 10;
  if (opts.email) {
    claims.email = opts.email;
    claims.email_verified = opts.emailVerified ?? true;
  }
  const jwt = new SignJWT(claims)
    .setProtectedHeader({ alg: "RS256", kid: KID, typ: "JWT" })
    .setIssuer(opts.iss ?? ISS)
    .setAudience(opts.aud ?? PROJECT)
    .setIssuedAt(opts.iat ?? now - 10)
    .setExpirationTime(opts.exp ?? now + 3600);
  if (opts.sub !== null) jwt.setSubject(opts.sub ?? "uid-123");
  return jwt.sign(privateKey);
}

function validPayload(): Record<string, unknown> {
  const now = Math.floor(Date.now() / 1000);
  return {
    iss: ISS, aud: PROJECT, sub: "uid-123", iat: now - 10, exp: now + 3600, auth_time: now - 10,
    firebase: { sign_in_provider: "google.com" },
  };
}

// A test app with one anonymous-friendly and one registered-only route.
const app = new Hono<AppEnv>();
app.onError(onError);
app.get("/any", requireUser(), (c) => c.json({ user: c.get("user") }));
app.get("/registered", requireUser({ allowAnonymous: false }), (c) => c.json({ user: c.get("user") }));
// Two layers: the outer one verifies, the inner one only re-checks anonymity.
app.use("/layered/*", requireUser());
app.get("/layered/registered", requireUser({ allowAnonymous: false }), (c) => c.json({ user: c.get("user") }));

function call(path: string, auth?: string): Promise<Response> {
  const headers = auth === undefined ? undefined : { authorization: auth };
  return Promise.resolve(app.fetch(new Request(`https://api.test${path}`, { headers }), env));
}
const bearer = (t: string) => `Bearer ${t}`;

async function expectUnauthorized(res: Response) {
  expect(res.status).toBe(401);
  // Generic: the response never says which check failed.
  expect(await res.json()).toEqual({ error: { code: "unauthorized", message: "Authentication required" } });
}

describe("requireUser: valid tokens", () => {
  it("accepts a valid anonymous token", async () => {
    const res = await call("/any", bearer(await firebaseToken()));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ user: { uid: "uid-123", isAnonymous: true, provider: "anonymous" } });
  });

  it("accepts a registered token and exposes email and provider", async () => {
    const t = await firebaseToken({ provider: "google.com", email: "p@yz.test", sub: "uid-g" });
    const res = await call("/registered", bearer(t));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ user: { uid: "uid-g", isAnonymous: false, provider: "google.com", email: "p@yz.test" } });
  });

  it("leaves out an unverified email", async () => {
    const t = await firebaseToken({ provider: "password", email: "not-mine@yz.test", emailVerified: false, sub: "uid-p" });
    const res = await call("/any", bearer(t));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ user: { uid: "uid-p", isAnonymous: false, provider: "password" } });
  });

  it("allows 60 s of clock skew on iat and auth_time", async () => {
    const now = Math.floor(Date.now() / 1000);
    const res = await call("/any", bearer(await firebaseToken({ iat: now + 30, authTime: now + 30 })));
    expect(res.status).toBe(200);
  });

  it("accepts a 128-character uid and a lowercase bearer scheme", async () => {
    const res = await call("/any", `bearer ${await firebaseToken({ sub: "u".repeat(128) })}`);
    expect(res.status).toBe(200);
  });
});

describe("requireUser: rejected tokens (401)", () => {
  it("missing Authorization header", async () => {
    await expectUnauthorized(await call("/any"));
  });

  it("non-Bearer scheme", async () => {
    await expectUnauthorized(await call("/any", `Basic ${await firebaseToken()}`));
  });

  it("garbage token", async () => {
    await expectUnauthorized(await call("/any", bearer("not.a.jwt")));
  });

  it("expired", async () => {
    const now = Math.floor(Date.now() / 1000);
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ iat: now - 7200, exp: now - 120 }))));
  });

  it("wrong audience", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ aud: "someone-elses-project" }))));
  });

  it("wrong issuer", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ iss: "https://securetoken.google.com/other" }))));
  });

  it("alg: none", async () => {
    const header = base64url.encode(JSON.stringify({ alg: "none", typ: "JWT" }));
    const body = base64url.encode(JSON.stringify(validPayload()));
    await expectUnauthorized(await call("/any", bearer(`${header}.${body}.`)));
  });

  it("HS256 signed with the public key (key confusion)", async () => {
    const forged = await new SignJWT(validPayload())
      .setProtectedHeader({ alg: "HS256", kid: KID, typ: "JWT" })
      .sign(new TextEncoder().encode(publicPem));
    await expectUnauthorized(await call("/any", bearer(forged)));
  });

  it("signed by a different RSA key with the same kid", async () => {
    const other = await generateKeyPair("RS256");
    const forged = await new SignJWT(validPayload()).setProtectedHeader({ alg: "RS256", kid: KID }).sign(other.privateKey);
    await expectUnauthorized(await call("/any", bearer(forged)));
  });

  it("tampered payload", async () => {
    const [h, , s] = (await firebaseToken()).split(".");
    const body = base64url.encode(JSON.stringify({ ...validPayload(), sub: "someone-else" }));
    await expectUnauthorized(await call("/any", bearer(`${h}.${body}.${s}`)));
  });

  it("missing sub", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ sub: null }))));
  });

  it("empty sub", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ sub: "" }))));
  });

  it("sub longer than 128 characters", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ sub: "u".repeat(129) }))));
  });

  it("auth_time in the future", async () => {
    const now = Math.floor(Date.now() / 1000);
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ authTime: now + 600 }))));
  });

  it("missing auth_time", async () => {
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ authTime: null }))));
  });

  it("iat in the future", async () => {
    const now = Math.floor(Date.now() / 1000);
    await expectUnauthorized(await call("/any", bearer(await firebaseToken({ iat: now + 600 }))));
  });

  it("missing kid", async () => {
    const t = await new SignJWT(validPayload()).setProtectedHeader({ alg: "RS256" }).sign(privateKey);
    await expectUnauthorized(await call("/any", bearer(t)));
  });

  it("unknown kid", async () => {
    const t = await new SignJWT(validPayload()).setProtectedHeader({ alg: "RS256", kid: "rotated-away" }).sign(privateKey);
    await expectUnauthorized(await call("/any", bearer(t)));
  });
});

describe("requireUser: anonymous users on registered-only routes", () => {
  it("403 for an anonymous token when allowAnonymous is false", async () => {
    const res = await call("/registered", bearer(await firebaseToken({ provider: "anonymous" })));
    expect(res.status).toBe(403);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("registration_required");
  });

  it("a second requireUser re-checks anonymity without verifying again", async () => {
    const anon = await call("/layered/registered", bearer(await firebaseToken({ provider: "anonymous" })));
    expect(anon.status).toBe(403);
    const reg = await call("/layered/registered", bearer(await firebaseToken({ provider: "password" })));
    expect(reg.status).toBe(200);
  });
});

describe("requireUser: JWKS", () => {
  it("503, not 401, when the JWKS cannot be fetched", async () => {
    jwksServer.fail = true;
    const res = await call("/any", bearer(await firebaseToken()));
    expect(res.status).toBe(503);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("auth_unavailable");
  });

  it("503 when the JWKS fetch throws (network error)", async () => {
    __setFirebaseJwksFetch(async () => {
      throw new TypeError("network down");
    });
    expect((await call("/any", bearer(await firebaseToken()))).status).toBe(503);
  });

  it("fetches Google's securetoken JWKS once for many requests", async () => {
    for (let i = 0; i < 5; i++) {
      expect((await call("/any", bearer(await firebaseToken({ sub: `uid-${i}` })))).status).toBe(200);
    }
    // A bad token does not trigger a refetch either (same kid, bad signature).
    const other = await generateKeyPair("RS256");
    const forged = await new SignJWT(validPayload()).setProtectedHeader({ alg: "RS256", kid: KID }).sign(other.privateKey);
    expect((await call("/any", bearer(forged))).status).toBe(401);
    expect(jwksServer.calls).toBe(1);
    expect(jwksServer.urls).toEqual([FIREBASE_JWKS_URL]);
  });

  it("does not fetch the JWKS for a token rejected before key lookup", async () => {
    await call("/any");
    await call("/any", bearer("not.a.jwt"));
    expect(jwksServer.calls).toBe(0);
  });
});

describe("/v1 routing", () => {
  const worker = (path: string, init?: RequestInit) => exports.default.fetch(new Request(`https://api.test${path}`, init));

  it("GET /v1/packs stays public", async () => {
    expect((await worker("/v1/packs")).status).toBe(200);
  });

  it("GET /v1/config is not behind auth", async () => {
    jwksServer.fail = true; // auth would answer 503; the public path never reaches it
    expect((await worker("/v1/config")).status).toBe(200);
  });

  it("any other /v1 route needs a token", async () => {
    expect((await worker("/v1/sessions", { method: "POST" })).status).toBe(401);
    expect((await worker("/v1/me")).status).toBe(401);
    // Public is GET-only.
    expect((await worker("/v1/packs", { method: "POST" })).status).toBe(401);
  });

  it("an authenticated request passes the /v1 middleware", async () => {
    const res = await worker("/v1/me", { headers: { authorization: bearer(await firebaseToken()) } });
    // No /v1/me route yet (P3S1 task 3), so auth passes and routing 404s.
    expect(res.status).toBe(404);
  });
});
