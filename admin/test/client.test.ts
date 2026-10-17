import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { API_BASE, ApiError, apiFetch, apiFetchBlob, noContent } from "../src/api/client";
import { errorMessage, errorTitle } from "../src/queryClient";

function stubFetch(impl: (url: string, init: RequestInit) => Promise<Response>) {
  const fn = vi.fn(impl);
  vi.stubGlobal("fetch", fn);
  return fn;
}

afterEach(() => vi.unstubAllGlobals());

describe("apiFetch", () => {
  it("parses a JSON body with the schema and sends credentials", async () => {
    const fetch = stubFetch(async () => Response.json({ ok: true }));
    await expect(apiFetch("/admin/x", z.object({ ok: z.boolean() }))).resolves.toEqual({ ok: true });
    const [url, init] = fetch.mock.calls[0]!;
    expect(url).toBe(`${API_BASE}/admin/x`);
    expect(init.credentials).toBe("include");
  });

  it("accepts 204 No Content", async () => {
    stubFetch(async () => new Response(null, { status: 204 }));
    await expect(apiFetch("/admin/x", noContent, { method: "DELETE" })).resolves.toBeUndefined();
  });

  it("sends `json` as a JSON body with the content type", async () => {
    const fetch = stubFetch(async () => Response.json({}));
    await apiFetch("/admin/x", z.object({}), { method: "POST", json: { a: 1 } });
    const [, init] = fetch.mock.calls[0]!;
    expect(init.body).toBe('{"a":1}');
    expect(new Headers(init.headers).get("content-type")).toBe("application/json");
  });

  it("leaves a FormData body and its content type to the browser", async () => {
    const fetch = stubFetch(async () => Response.json({}));
    const form = new FormData();
    form.set("file", new Blob(["x"]), "a.mp3");
    await apiFetch("/admin/x", z.object({}), { method: "POST", body: form });
    const [, init] = fetch.mock.calls[0]!;
    expect(init.body).toBe(form);
    expect(new Headers(init.headers).has("content-type")).toBe(false);
  });

  it("throws the Worker's error code and message with the request id", async () => {
    stubFetch(async () =>
      Response.json(
        { error: { code: "forbidden", message: "Editors cannot do that" } },
        { status: 403, headers: { "x-request-id": "req-1" } },
      ),
    );
    const err = await apiFetch("/admin/x", z.object({})).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 403, code: "forbidden", message: "Editors cannot do that", requestId: "req-1" });
  });

  it("throws http_error for a non-JSON error body", async () => {
    stubFetch(async () => new Response("<html>bad gateway</html>", { status: 502 }));
    await expect(apiFetch("/admin/x", z.object({}))).rejects.toMatchObject({ status: 502, code: "http_error" });
  });

  it("throws bad_response for a body that doesn't match the schema", async () => {
    stubFetch(async () => Response.json({ nope: 1 }));
    await expect(apiFetch("/admin/x", z.object({ ok: z.boolean() }))).rejects.toMatchObject({ code: "bad_response" });
  });

  it("throws a network error that mentions an expired sign-in when fetch fails", async () => {
    stubFetch(async () => {
      throw new TypeError("Failed to fetch");
    });
    const err = await apiFetch("/admin/x", z.object({})).catch((e: unknown) => e);
    expect(err).toMatchObject({ status: 0, code: "network" });
    expect((err as Error).message).toMatch(/reload the page to sign in again/);
  });
});

describe("error notifications", () => {
  it("titles errors by status", () => {
    expect(errorTitle(new ApiError(0, "network", "x"))).toBe("Can't reach the API");
    expect(errorTitle(new ApiError(401, "unauthorized", "x"))).toBe("Sign-in required");
    expect(errorTitle(new ApiError(403, "forbidden", "x"))).toBe("Not allowed");
    expect(errorTitle(new ApiError(500, "internal", "x"))).toBe("Request failed");
    expect(errorTitle(new Error("x"))).toBe("Something went wrong");
  });

  it("adds the request id to the message when there is one", () => {
    expect(errorMessage(new ApiError(500, "internal", "Internal server error", "abc"))).toBe(
      "Internal server error (request abc)",
    );
    expect(errorMessage(new ApiError(0, "network", "offline"))).toBe("offline");
  });
});

describe("apiFetchBlob", () => {
  it("returns the file and sends the Access cookie", async () => {
    const fetch = stubFetch(async () => new Response("a,b\r\n1,2\r\n", { headers: { "content-type": "text/csv" } }));
    const blob = await apiFetchBlob("/admin/reports/royalty?from=a");
    expect(await blob.text()).toBe("a,b\r\n1,2\r\n");
    const [url, init] = fetch.mock.calls[0]!;
    expect(url).toBe(`${API_BASE}/admin/reports/royalty?from=a`);
    expect(init.credentials).toBe("include");
  });

  it("throws the Worker's error, not a broken download", async () => {
    stubFetch(async () => Response.json({ error: { code: "forbidden", message: "Requires role: admin" } }, { status: 403 }));
    await expect(apiFetchBlob("/x")).rejects.toMatchObject({ status: 403, code: "forbidden", message: "Requires role: admin" });
  });

  it("throws a plain error when the failure has no JSON body", async () => {
    stubFetch(async () => new Response("<html>bad gateway</html>", { status: 502 }));
    await expect(apiFetchBlob("/x")).rejects.toMatchObject({ status: 502, code: "http_error" });
  });

  it("explains an unreachable API", async () => {
    stubFetch(async () => {
      throw new TypeError("Failed to fetch");
    });
    await expect(apiFetchBlob("/x")).rejects.toMatchObject({ status: 0, code: "network" });
  });
});
