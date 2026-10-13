import { env, exports } from "cloudflare:workers";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { adminUsers } from "../src/db/schema";
import { __setTestKeyResolver, ACCESS_HEADER } from "../src/lib/accessAuth";

const TEAM = "https://yz.cloudflareaccess.com";
const AUD = "test-access-aud";
const SERVICE_ID = "test-service.client";

let privateKey: CryptoKey;

type Claims = { email?: string; common_name?: string };

async function token(
  claims: Claims,
  opts: { iss?: string; aud?: string; expiresIn?: string | number; kid?: string } = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const exp = opts.expiresIn ?? "1h";
  const jwt = new SignJWT({ ...claims })
    .setProtectedHeader({ alg: "RS256", kid: opts.kid ?? "test-key" })
    .setIssuedAt(now)
    .setIssuer(opts.iss ?? TEAM)
    .setAudience(opts.aud ?? AUD);
  if (typeof exp === "number") jwt.setExpirationTime(exp);
  else jwt.setExpirationTime(exp);
  return jwt.sign(privateKey);
}

function req(path: string, jwt?: string): Promise<Response> {
  const headers = new Headers();
  if (jwt) headers.set(ACCESS_HEADER, jwt);
  return exports.default.fetch(new Request(`https://api.test${path}`, { headers }));
}

beforeAll(async () => {
  const pair = await generateKeyPair("RS256", { extractable: true });
  privateKey = pair.privateKey;
  const jwk = await exportJWK(pair.publicKey);
  jwk.kid = "test-key";
  jwk.alg = "RS256";
  __setTestKeyResolver(createLocalJWKSet({ keys: [jwk] }));

  await db(env)
    .insert(adminUsers)
    .values([
      { email: "admin@yz.test", role: "admin", createdAt: Date.now() },
      { email: "editor@yz.test", role: "editor", createdAt: Date.now() },
    ])
    .onConflictDoNothing();
});

afterAll(() => __setTestKeyResolver(null));

describe("requireAdmin on /admin/whoami", () => {
  it("accepts a valid admin token", async () => {
    const res = await req("/admin/whoami", await token({ email: "admin@yz.test" }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ admin: { email: "admin@yz.test", role: "admin" } });
  });

  it("401 with no header", async () => {
    const res = await req("/admin/whoami");
    expect(res.status).toBe(401);
  });

  it("401 on wrong audience", async () => {
    const res = await req("/admin/whoami", await token({ email: "admin@yz.test" }, { aud: "someone-else" }));
    expect(res.status).toBe(401);
  });

  it("401 on wrong issuer", async () => {
    const res = await req("/admin/whoami", await token({ email: "admin@yz.test" }, { iss: "https://evil.example" }));
    expect(res.status).toBe(401);
  });

  it("401 on an expired token", async () => {
    const res = await req("/admin/whoami", await token({ email: "admin@yz.test" }, { expiresIn: Math.floor(Date.now() / 1000) - 60 }));
    expect(res.status).toBe(401);
  });

  it("403 for an unknown email", async () => {
    const res = await req("/admin/whoami", await token({ email: "ghost@yz.test" }));
    expect(res.status).toBe(403);
  });

  it("403 when a service token hits a human route", async () => {
    const res = await req("/admin/whoami", await token({ common_name: SERVICE_ID }));
    expect(res.status).toBe(403);
  });

  it("accepts an editor and reports the role", async () => {
    const res = await req("/admin/whoami", await token({ email: "editor@yz.test" }));
    expect(await res.json()).toEqual({ admin: { email: "editor@yz.test", role: "editor" } });
  });
});

describe("requireService on /admin/ingest/whoami", () => {
  it("accepts the ingest service token", async () => {
    const res = await req("/admin/ingest/whoami", await token({ common_name: SERVICE_ID }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ service: { clientId: SERVICE_ID } });
  });

  it("401 with no header", async () => {
    expect((await req("/admin/ingest/whoami")).status).toBe(401);
  });

  it("403 when a human token hits an ingest route", async () => {
    const res = await req("/admin/ingest/whoami", await token({ email: "admin@yz.test" }));
    expect(res.status).toBe(403);
  });

  it("403 for a service token with the wrong common_name", async () => {
    const res = await req("/admin/ingest/whoami", await token({ common_name: "intruder.client" }));
    expect(res.status).toBe(403);
  });
});

describe("dev bypass", () => {
  it("allows DEV_ADMIN_EMAIL with no header only when ENV=dev", async () => {
    const e = env as { ENV: string; DEV_ADMIN_EMAIL?: string };
    const savedEnv = e.ENV;
    const savedEmail = e.DEV_ADMIN_EMAIL;
    try {
      e.ENV = "dev";
      e.DEV_ADMIN_EMAIL = "admin@yz.test";
      const ok = await req("/admin/whoami");
      expect(ok.status).toBe(200);
      expect(await ok.json()).toEqual({ admin: { email: "admin@yz.test", role: "admin" } });

      // Same bypass must not work outside dev.
      e.ENV = "prod";
      expect((await req("/admin/whoami")).status).toBe(401);
    } finally {
      e.ENV = savedEnv;
      e.DEV_ADMIN_EMAIL = savedEmail;
    }
  });
});

describe("never 500 on bad input", () => {
  it("garbage token is 401, not 500", async () => {
    expect((await req("/admin/whoami", "not.a.jwt")).status).toBe(401);
    expect((await req("/admin/ingest/whoami", "not.a.jwt")).status).toBe(401);
  });
});
