// ADMIN_LOGIN=firebase (admins sign in with Google, Bearer token) and the INGEST_TOKEN shared secret:
// the sign-in paths for an admin site and API on unrelated hostnames, where Cloudflare Access cannot help.
import { env } from "cloudflare:workers";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import app from "../src/index";
import { MIN_INGEST_TOKEN_LENGTH } from "../src/lib/accessAuth";
import { installFirebaseJwks, installTestJwks, removeFirebaseJwks, removeTestJwks, seedAdmins, SERVICE_ID, signAccessJwt, signFirebaseToken } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await installFirebaseJwks();
  await seedAdmins();
});
afterAll(() => {
  removeTestJwks();
  removeFirebaseJwks();
});

const INGEST_TOKEN = "t".repeat(MIN_INGEST_TOKEN_LENGTH);

function call(path: string, vars: Record<string, string | undefined>, headers: Record<string, string> = {}) {
  return app.fetch(new Request(`https://api.test${path}`, { headers }), { ...env, ...vars });
}
const firebase = (headers: Record<string, string> = {}) => call("/admin/whoami", { ADMIN_LOGIN: "firebase" }, headers);
const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
const google = (email: string, o: { emailVerified?: boolean; provider?: string } = {}) =>
  signFirebaseToken(`uid-${email}`, { provider: o.provider ?? "google.com", email, emailVerified: o.emailVerified });

describe("ADMIN_LOGIN=firebase", () => {
  it("accepts a Google sign-in whose verified email is an admin", async () => {
    const res = await firebase(bearer(await google("admin@yz.test")));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ admin: { email: "admin@yz.test", role: "admin" } });
  });

  it("reports an editor's role", async () => {
    const res = await firebase(bearer(await google("editor@yz.test")));
    expect(await res.json()).toEqual({ admin: { email: "editor@yz.test", role: "editor" } });
  });

  it("401 without a token, or with a bad one", async () => {
    expect((await firebase()).status).toBe(401);
    expect((await firebase(bearer("not.a.jwt"))).status).toBe(401);
  });

  it("403 for a Google account that is not an admin", async () => {
    expect((await firebase(bearer(await google("someone@yz.test")))).status).toBe(403);
  });

  it("403 for an admin's email that is not verified, or not from a Google sign-in", async () => {
    expect((await firebase(bearer(await google("admin@yz.test", { emailVerified: false })))).status).toBe(403);
    expect((await firebase(bearer(await google("admin@yz.test", { provider: "password" })))).status).toBe(403);
    expect((await firebase(bearer(await signFirebaseToken("guest")))).status).toBe(403);
  });

  it("ignores an Access token: one sign-in mode at a time", async () => {
    const jwt = await signAccessJwt({ email: "admin@yz.test" });
    expect((await firebase({ "cf-access-jwt-assertion": jwt })).status).toBe(401);
  });
});

describe("ADMIN_LOGIN=access (the default)", () => {
  it("ignores a Firebase token", async () => {
    const token = await google("admin@yz.test");
    expect((await call("/admin/whoami", { ADMIN_LOGIN: undefined }, bearer(token))).status).toBe(401);
    expect((await call("/admin/whoami", { ADMIN_LOGIN: "Firebase" }, bearer(token))).status).toBe(401);
  });
});

describe("INGEST_TOKEN", () => {
  const ingest = (vars: Record<string, string | undefined>, headers: Record<string, string>) => call("/admin/ingest/whoami", vars, headers);

  it("lets the ingest jobs in with the shared secret", async () => {
    const res = await ingest({ INGEST_TOKEN }, bearer(INGEST_TOKEN));
    expect(res.status).toBe(200);
  });

  it("401 for a wrong secret", async () => {
    expect((await ingest({ INGEST_TOKEN }, bearer(`${INGEST_TOKEN}x`))).status).toBe(401);
    expect((await ingest({ INGEST_TOKEN }, bearer("short"))).status).toBe(401);
  });

  it("is ignored when unset or too short, leaving only the Access service token", async () => {
    expect((await ingest({ INGEST_TOKEN: undefined }, bearer(INGEST_TOKEN))).status).toBe(401);
    const short = "s".repeat(MIN_INGEST_TOKEN_LENGTH - 1);
    expect((await ingest({ INGEST_TOKEN: short }, bearer(short))).status).toBe(401);
    const jwt = await signAccessJwt({ common_name: SERVICE_ID });
    expect((await ingest({ INGEST_TOKEN }, { "cf-access-jwt-assertion": jwt })).status).toBe(200);
  });

  it("never lets anyone into the admin routes", async () => {
    for (const mode of ["access", "firebase"]) {
      expect((await call("/admin/whoami", { INGEST_TOKEN, ADMIN_LOGIN: mode }, bearer(INGEST_TOKEN))).status).toBe(401);
    }
  });
});

describe("CORS", () => {
  it("lets the admin origin send the Authorization header", async () => {
    const origin = (env as { ADMIN_ORIGIN: string }).ADMIN_ORIGIN;
    const res = await app.fetch(
      new Request("https://api.test/admin/whoami", {
        method: "OPTIONS",
        headers: { origin, "access-control-request-method": "GET", "access-control-request-headers": "authorization" },
      }),
      env,
    );
    expect(res.headers.get("access-control-allow-origin")).toBe(origin);
    expect(res.headers.get("access-control-allow-headers")?.toLowerCase()).toContain("authorization");
  });
});
