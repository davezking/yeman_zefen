import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { adminLoginFrom } from "../src/auth/login";

const token = vi.hoisted(() => ({ value: "tok" as string | null }));
vi.mock("../src/auth/firebase", () => ({ idToken: async () => token.value }));

const { ApiError, apiFetch, apiFetchBlob } = await import("../src/api/client");

function stubFetch() {
  const fn = vi.fn(async (_url: string, _init: RequestInit) => Response.json({ ok: true }));
  vi.stubGlobal("fetch", fn);
  return fn;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  token.value = "tok";
});

describe("adminLoginFrom", () => {
  it("is firebase only when asked for exactly, like the Worker", () => {
    expect(adminLoginFrom({ VITE_ADMIN_LOGIN: "firebase" })).toBe("firebase");
    for (const v of [undefined, "", "access", "Firebase"]) expect(adminLoginFrom({ VITE_ADMIN_LOGIN: v })).toBe("access");
  });
});

describe("requests with VITE_ADMIN_LOGIN=firebase", () => {
  it("send the ID token as a Bearer token and no cookie", async () => {
    vi.stubEnv("VITE_ADMIN_LOGIN", "firebase");
    const fetch = stubFetch();
    await apiFetch("/admin/x", z.object({ ok: z.boolean() }), { headers: { "x-extra": "1" } });
    const [, init] = fetch.mock.calls[0]!;
    const headers = new Headers(init.headers);
    expect(headers.get("authorization")).toBe("Bearer tok");
    expect(headers.get("x-extra")).toBe("1");
    expect(init.credentials).toBe("omit");
  });

  it("do the same for file downloads", async () => {
    vi.stubEnv("VITE_ADMIN_LOGIN", "firebase");
    const fetch = stubFetch();
    await apiFetchBlob("/admin/report.csv");
    expect(new Headers(fetch.mock.calls[0]![1].headers).get("authorization")).toBe("Bearer tok");
  });

  it("are not sent at all when signed out", async () => {
    vi.stubEnv("VITE_ADMIN_LOGIN", "firebase");
    token.value = null;
    const fetch = stubFetch();
    await expect(apiFetch("/admin/x", z.object({}))).rejects.toMatchObject({ status: 401, code: "signed_out" });
    await expect(apiFetch("/admin/x", z.object({}))).rejects.toBeInstanceOf(ApiError);
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("requests with Cloudflare Access (the default)", () => {
  it("send the cookie and no Bearer token", async () => {
    const fetch = stubFetch();
    await apiFetch("/admin/x", z.object({ ok: z.boolean() }));
    const [, init] = fetch.mock.calls[0]!;
    expect(new Headers(init.headers).get("authorization")).toBeNull();
    expect(init.credentials).toBe("include");
  });
});
