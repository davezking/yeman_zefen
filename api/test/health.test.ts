import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("GET /health", () => {
  it("returns ok with the env name and a request id", async () => {
    const res = await exports.default.fetch("http://api.test/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, env: "dev" });
    expect(res.headers.get("x-request-id")).toBeTruthy();
  });

  it("returns the JSON error shape for unknown routes", async () => {
    const res = await exports.default.fetch("http://api.test/nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Route not found" } });
  });
});
