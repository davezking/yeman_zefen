import { exports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { hashUid } from "../src/lib/requestLog";

afterEach(() => vi.restoreAllMocks());

/** The request-log lines written during one fetch, parsed. */
async function logsFor(url: string, init?: RequestInit) {
  const spy = vi.spyOn(console, "log").mockImplementation(() => {});
  const res = await exports.default.fetch(url, init);
  const lines = spy.mock.calls.map((args) => JSON.parse(String(args[0])));
  return { res, lines };
}

describe("request log", () => {
  it("writes one JSON line per request with the route pattern and status", async () => {
    const { res, lines } = await logsFor("http://api.test/health");
    expect(res.status).toBe(200);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      requestId: res.headers.get("x-request-id"),
      route: "/health",
      status: 200,
    });
    expect(typeof lines[0].latencyMs).toBe("number");
    expect(lines[0].uidHash).toBeUndefined();
  });

  it("names the error code of a failed request and never logs the body", async () => {
    const { lines } = await logsFor("http://api.test/nope", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ secret: "do-not-log-me" }),
    });
    expect(lines[0]).toMatchObject({ route: "/*", status: 404, errorCode: "not_found" });
    expect(JSON.stringify(lines)).not.toContain("do-not-log-me");
  });

  it("hashes the UID to 16 hex characters", async () => {
    const hash = await hashUid("player-123");
    expect(hash).toMatch(/^[0-9a-f]{16}$/);
    expect(hash).not.toContain("player-123");
    expect(await hashUid("player-123")).toBe(hash);
    expect(await hashUid("player-456")).not.toBe(hash);
  });
});
