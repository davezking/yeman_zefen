// GET /admin/tracks/:id/source-url (presigned read of the private source audio) and GET /admin/jobs?id=.
import { env } from "cloudflare:workers";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { presignSourceUrl, SOURCE_URL_TTL_SECONDS } from "../src/lib/sourceUrl";
import { api, installTestJwks, makeArtist, makeJob, makeTrack, rawRequest, removeTestJwks, resetCatalog, seedAdmins } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: response shapes are asserted below

const creds = { R2_ENDPOINT: "https://acct.r2.cloudflarestorage.com", R2_ACCESS_KEY_ID: "AKID", R2_SECRET_ACCESS_KEY: "secret" };
const mutable = env as unknown as Record<string, string | undefined>;
const saved = { ...mutable };
afterEach(() => {
  for (const k of Object.keys(creds)) {
    if (saved[k] === undefined) delete mutable[k];
    else mutable[k] = saved[k];
  }
});

describe("presignSourceUrl", () => {
  it("signs a path-style GET that lasts 10 minutes", async () => {
    const now = Date.UTC(2026, 9, 14, 12, 0, 0);
    const signed = await presignSourceUrl({ ...env, ...creds }, "source/12/a b.mp3", now + 750);
    expect(signed.expiresAt).toBe(now + 600_000);
    const url = new URL(signed.url);
    expect(url.origin).toBe("https://acct.r2.cloudflarestorage.com");
    expect(url.pathname).toBe("/yz-source/source/12/a%20b.mp3");
    expect(url.searchParams.get("X-Amz-Expires")).toBe(String(SOURCE_URL_TTL_SECONDS));
    expect(SOURCE_URL_TTL_SECONDS).toBe(600);
    expect(url.searchParams.get("X-Amz-Date")).toBe("20261014T120000Z");
    expect(url.searchParams.get("X-Amz-Algorithm")).toBe("AWS4-HMAC-SHA256");
    expect(url.searchParams.get("X-Amz-Credential")).toContain("AKID/20261014/auto/s3/aws4_request");
    expect(url.searchParams.get("X-Amz-Signature")).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("GET /admin/tracks/:id/source-url", () => {
  it("returns a signed url and its expiry", async () => {
    Object.assign(mutable, creds);
    const track = await makeTrack((await makeArtist("አርቲስት")).id, { sourceAudioKey: "source/1.mp3" });
    const before = Math.floor(Date.now() / 1000) * 1000;
    const res = await api(`/admin/tracks/${track.id}/source-url`, { method: "GET", as: "editor" });
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(new URL(body.url).pathname).toBe("/yz-source/source/1.mp3");
    expect(body.expiresAt).toBeGreaterThanOrEqual(before + 600_000);
    expect(body.expiresAt).toBeLessThanOrEqual(Date.now() + 600_000);
  });

  it("404s for an unknown track and for one with no source audio", async () => {
    Object.assign(mutable, creds);
    expect((await api("/admin/tracks/9999/source-url", { method: "GET" })).status).toBe(404);
    const track = await makeTrack((await makeArtist("አርቲስት")).id);
    const res = await api(`/admin/tracks/${track.id}/source-url`, { method: "GET" });
    expect(res.status).toBe(404);
    expect((await json(res)).error.code).toBe("no_source_audio");
  });

  it("503s when the R2 credentials are missing, and 401s without Access", async () => {
    const track = await makeTrack((await makeArtist("አርቲስት")).id, { sourceAudioKey: "source/1.mp3" });
    const res = await api(`/admin/tracks/${track.id}/source-url`, { method: "GET" });
    expect(res.status).toBe(503);
    expect((await json(res)).error.code).toBe("source_signing_unconfigured");
    expect((await rawRequest(`/admin/tracks/${track.id}/source-url`)).status).toBe(401);
  });
});

describe("GET /admin/jobs?id=", () => {
  it("returns only that job", async () => {
    await makeJob("scrape", "succeeded");
    const job = await makeJob("recut", "running");
    const body = await json(await api(`/admin/jobs?id=${job.id}`, { method: "GET" }));
    expect(body.jobs).toHaveLength(1);
    expect(body.jobs[0]).toMatchObject({ id: job.id, kind: "recut", status: "running" });
  });

  it("404s for a missing job and 400s for a bad id", async () => {
    expect((await api("/admin/jobs?id=999999", { method: "GET" })).status).toBe(404);
    expect((await api("/admin/jobs?id=abc", { method: "GET" })).status).toBe(400);
  });
});
