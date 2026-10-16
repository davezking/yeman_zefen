import { env, exports } from "cloudflare:workers";
import app from "../src/index";
import { describe, expect, it } from "vitest";

const DEFAULTS = {
  interstitialEveryRounds: 3,
  registerPromptAfterSessions: 5,
  registerPromptCooldownDays: 7,
  minAppVersion: "0.1.0",
  defaultClipMs: 10_000,
};

describe("GET /v1/config", () => {
  it("answers publicly with the tunables from the vars, cacheable for 10 minutes", async () => {
    const res = await exports.default.fetch(new Request("https://api.test/v1/config"));
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=600");
    expect(await res.json()).toEqual(DEFAULTS);
  });

  it("answers HEAD without auth too", async () => {
    const res = await exports.default.fetch(new Request("https://api.test/v1/config", { method: "HEAD" }));
    expect(res.status).toBe(200);
  });

  it("rejects POST (not a public route)", async () => {
    const res = await exports.default.fetch(new Request("https://api.test/v1/config", { method: "POST" }));
    expect(res.status).toBe(401);
  });

  it("changing a var changes the answer (a redeploy in production)", async () => {
    const res = await app.fetch(new Request("https://api.test/v1/config"), { ...env, CONFIG_INTERSTITIAL_EVERY_ROUNDS: "5", CONFIG_MIN_APP_VERSION: "1.2.0" });
    const config = await res.json();
    expect(config).toMatchObject({ interstitialEveryRounds: 5, minAppVersion: "1.2.0" });
  });

  it.each([
    ["CONFIG_INTERSTITIAL_EVERY_ROUNDS", "0"],
    ["CONFIG_INTERSTITIAL_EVERY_ROUNDS", "three"],
    ["CONFIG_REGISTER_PROMPT_AFTER_SESSIONS", "-1"],
    ["CONFIG_MIN_APP_VERSION", "1.2"],
    ["CONFIG_DEFAULT_CLIP_MS", "500"],
    ["CONFIG_DEFAULT_CLIP_MS", undefined as unknown as string],
  ])("a bad %s (%s) is a 500 that names the var", async (name, value) => {
    const bad = { ...env, [name]: value };
    const res = await app.fetch(new Request("https://api.test/v1/config"), bad);
    expect(res.status).toBe(500);
    const body = (await res.json()) as { error: { code: string; message: string } };
    expect(body.error.code).toBe("config_invalid");
    expect(body.error.message).toContain(name);
  });
});
