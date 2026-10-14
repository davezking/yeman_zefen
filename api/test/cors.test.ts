import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { installTestJwks, rawRequest, removeTestJwks, seedAdmins, signAccessJwt } from "./helpers";

// wrangler.toml sets ADMIN_ORIGIN to the dev admin origin for tests.
const ADMIN = "http://localhost:5173";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});

afterAll(() => removeTestJwks());

describe("CORS on /admin/*", () => {
  it("allows the admin origin with credentials", async () => {
    const jwt = await signAccessJwt({ email: "admin@yz.test" });
    const res = await rawRequest("/admin/whoami", { jwt, headers: { origin: ADMIN } });
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBe(ADMIN);
    expect(res.headers.get("access-control-allow-credentials")).toBe("true");
    expect(res.headers.get("access-control-expose-headers")?.toLowerCase()).toContain("x-request-id");
  });

  it("answers the preflight without an Access token", async () => {
    const res = await rawRequest("/admin/tracks", {
      method: "OPTIONS",
      headers: { origin: ADMIN, "access-control-request-method": "PATCH" },
    });
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe(ADMIN);
    expect(res.headers.get("access-control-allow-methods")).toContain("PATCH");
  });

  it("keeps the CORS headers on error responses, so the SPA can read the error body", async () => {
    const res = await rawRequest("/admin/whoami", { headers: { origin: ADMIN } });
    expect(res.status).toBe(401);
    expect(res.headers.get("access-control-allow-origin")).toBe(ADMIN);
    expect(res.headers.get("access-control-expose-headers")?.toLowerCase()).toContain("x-request-id");
  });

  it("sends no allow-origin header to any other origin", async () => {
    const jwt = await signAccessJwt({ email: "admin@yz.test" });
    const res = await rawRequest("/admin/whoami", { jwt, headers: { origin: "https://evil.example" } });
    expect(res.status).toBe(200);
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });

  it("does not add CORS headers to the health route", async () => {
    const res = await rawRequest("/health", { headers: { origin: ADMIN } });
    expect(res.headers.get("access-control-allow-origin")).toBeNull();
  });
});
