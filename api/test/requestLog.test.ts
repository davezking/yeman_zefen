import { exports } from "cloudflare:workers";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { hashUid } from "../src/lib/requestLog";
import { installFirebaseJwks, player, removeFirebaseJwks, signFirebaseToken } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);
afterEach(() => vi.restoreAllMocks());

/** The request-log lines written while [send] runs, parsed. */
async function logsOf(send: () => Promise<Response>) {
  const spy = vi.spyOn(console, "log").mockImplementation(() => {});
  const res = await send();
  const lines = spy.mock.calls.map((args) => JSON.parse(String(args[0])));
  spy.mockRestore();
  return { res, lines };
}

const logsFor = (url: string, init?: RequestInit) => logsOf(() => exports.default.fetch(url, init));

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

  it("logs the hashed UID and country of a signed-in player, never the token", async () => {
    const token = await signFirebaseToken("log-player-1");
    const { res, lines } = await logsOf(() => player("log-player-1", "/v1/me", { cf: { country: "ET" } }));
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      route: "/v1/me",
      status: res.status,
      uidHash: await hashUid("log-player-1"),
      country: "ET",
    });
    const text = JSON.stringify(lines);
    expect(text).not.toContain("log-player-1");
    expect(text).not.toContain(token.split(".")[1]);
  });

  it("names the endpoint and the ApiError code when a middleware rejects the request", async () => {
    const { lines } = await logsFor("http://api.test/v1/me", { headers: { authorization: "Bearer junk" } });
    expect(lines[0]).toMatchObject({ route: "/v1/me", status: 401, errorCode: "unauthorized" });
    expect(JSON.stringify(lines)).not.toContain("junk");
  });

  it("hashes the UID to 16 hex characters", async () => {
    const hash = await hashUid("player-123");
    expect(hash).toMatch(/^[0-9a-f]{16}$/);
    expect(hash).not.toContain("player-123");
    expect(await hashUid("player-123")).toBe(hash);
    expect(await hashUid("player-456")).not.toBe(hash);
  });
});
