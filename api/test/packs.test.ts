// Pack builder: eligibility, immutable manifests, version history, the public /v1/packs list.
import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { clips, trackGenres, tracks } from "../src/db/schema";
import { packManifest } from "../src/lib/packManifest";
import { publishVersion, requirePack } from "../src/lib/packs";
import { api, installTestJwks, makeArtist, makeTrack, rawRequest, removeTestJwks, resetCatalog, seedAdmins, signAccessJwt } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(async () => {
  await resetCatalog();
  const listed = await env.CLIPS.list({ prefix: "packs/" });
  await Promise.all(listed.objects.map((o) => env.CLIPS.delete(o.key)));
});
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: response shapes are asserted below

let n = 0;
/** An approved track with both clips ready, unless told otherwise. */
async function eligible(opts: { status?: "approved" | "ingested" | "retired"; middle?: "ready" | "pending"; generationId?: number } = {}) {
  n++;
  const artist = await makeArtist(`አርቲስት ${n}`, `Artist ${n}`);
  const track = await makeTrack(artist.id, { titleAm: `ዘፈን ${n}`, titleLatin: `Song ${n}`, status: opts.status ?? "approved", releaseYear: 1975, generationId: opts.generationId ?? null });
  for (const type of ["intro", "middle"] as const) {
    await db(env).insert(clips).values({
      trackId: track.id, type, startMs: 0, lengthMs: 10_000, status: type === "middle" ? (opts.middle ?? "ready") : "ready",
      r2Key: `clips/${track.id}/${type}-v1.mp3`, sha256: `${track.id}`.padStart(64, "a"), bytes: 100_000 + track.id,
    });
  }
  return track;
}

const createPack = async (body: Record<string, unknown> = {}) =>
  (await json(await api("/admin/packs", { body: { slug: "all", nameAm: "ሁሉም", nameEn: "Everything", ...body } }))).pack;
const publish = (id: number, body?: unknown) => api(`/admin/packs/${id}/versions`, { method: "POST", body: body ?? undefined });

describe("POST /admin/packs", () => {
  it("creates a pack, rejects a repeated slug, a bad slug and unknown filters", async () => {
    const res = await api("/admin/packs", { body: { slug: "all", nameAm: "ሁሉም", nameEn: "Everything" } });
    expect(res.status).toBe(201);
    expect((await json(res)).pack).toMatchObject({ slug: "all", currentVersion: null, versions: [], eligibleCount: 0 });
    const dup = await api("/admin/packs", { body: { slug: "all", nameAm: "x", nameEn: "x" } });
    expect(dup.status).toBe(409);
    expect((await json(dup)).error.code).toBe("slug_taken");
    expect((await api("/admin/packs", { body: { slug: "Bad Slug", nameAm: "x", nameEn: "x" } })).status).toBe(400);
    expect((await api("/admin/packs", { body: { slug: "g", nameAm: "x", nameEn: "x", genreId: 99999 } })).status).toBe(400);
  });
});

describe("publishing a version", () => {
  it("writes a manifest that matches the documented schema, with immutable cache headers", async () => {
    const a = await eligible();
    const b = await eligible();
    await db(env).insert(trackGenres).values([{ trackId: a.id, genreId: 1 }, { trackId: a.id, genreId: 2 }]);
    const pack = await createPack();
    expect(pack.eligibleCount).toBe(2);

    const res = await publish(pack.id);
    expect(res.status).toBe(201);
    const { published } = await json(res);
    expect(published).toMatchObject({ version: 1, trackCount: 2 });

    const object = await env.CLIPS.get("packs/all/v1/manifest.json");
    expect(object!.httpMetadata?.cacheControl).toBe("public, max-age=31536000, immutable");
    expect(object!.httpMetadata?.contentType).toBe("application/json");
    const manifest = packManifest.parse(await object!.json());
    expect(manifest).toMatchObject({ schema: 1, slug: "all", version: 1, names: { am: "ሁሉም", en: "Everything" }, generationId: null, genreId: null });
    expect(manifest.tracks.map((t) => t.id)).toEqual([a.id, b.id]);
    expect(manifest.tracks[0]).toMatchObject({ genreIds: [1, 2], releaseYear: 1975, artistLatin: expect.stringContaining("Artist") });
    expect(manifest.tracks[0]!.clips.intro.url).toBe(`${env.CDN_BASE_URL}/clips/${a.id}/intro-v1.mp3`);
    expect(manifest.totalBytes).toBe(published.totalBytes);

    const list = (await json(await api("/admin/packs"))).items[0];
    expect(list.currentVersion).toBe(1);
    expect(list.versions).toHaveLength(1);
    const members = await env.DB.prepare("SELECT track_id, intro_clip_id, middle_clip_id FROM pack_tracks").all();
    expect(members.results).toHaveLength(2);
    expect(members.results.every((r) => r.intro_clip_id && r.middle_clip_id)).toBe(true);
  });

  it("only takes approved tracks with both clips ready, and applies the pack's filter", async () => {
    const wanted = await eligible({ generationId: 2 });
    await eligible({ generationId: 3 });
    await eligible({ status: "ingested", generationId: 2 });
    await eligible({ middle: "pending", generationId: 2 });
    const pack = await createPack({ generationId: 2 });
    expect(pack.eligibleCount).toBe(1);
    const { published } = await json(await publish(pack.id));
    expect(published.trackCount).toBe(1);
    const manifest = packManifest.parse(await (await env.CLIPS.get("packs/all/v1/manifest.json"))!.json());
    expect(manifest.tracks.map((t) => t.id)).toEqual([wanted.id]);
  });

  it("validates an explicit track list", async () => {
    const ok = await eligible();
    const notApproved = await eligible({ status: "ingested" });
    const pack = await createPack();
    const bad = await publish(pack.id, { trackIds: [ok.id, notApproved.id] });
    expect(bad.status).toBe(409);
    const { error } = await json(bad);
    expect(error.code).toBe("tracks_not_eligible");
    expect(error.message).toContain(String(notApproved.id));
    expect((await publish(pack.id, { trackIds: [ok.id] })).status).toBe(201);
    expect((await publish(pack.id, { trackIds: [] })).status).toBe(400);
  });

  it("refuses an empty pack, and an unknown pack", async () => {
    const pack = await createPack();
    const res = await publish(pack.id);
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("no_eligible_tracks");
    expect((await publish(9999)).status).toBe(404);
  });

  it("never overwrites a manifest: versions count up, and a stray manifest is skipped", async () => {
    await eligible();
    const pack = await createPack();
    await publish(pack.id);
    const v1 = await (await env.CLIPS.get("packs/all/v1/manifest.json"))!.text();
    await env.CLIPS.put("packs/all/v2/manifest.json", "left behind by a publish that died");
    const second = await json(await publish(pack.id));
    expect(second.published.version).toBe(3);
    expect(await (await env.CLIPS.get("packs/all/v1/manifest.json"))!.text()).toBe(v1);
    expect(await (await env.CLIPS.get("packs/all/v2/manifest.json"))!.text()).toBe("left behind by a publish that died");
    const row = (await json(await api("/admin/packs"))).items[0];
    expect(row.versions.map((v: any) => v.version)).toEqual([3, 1]);
    expect(row.currentVersion).toBe(3);
  });

  it("keeps a retired track in the old version and leaves it out of the next", async () => {
    const stays = await eligible();
    const retired = await eligible();
    const pack = await createPack();
    await publish(pack.id);
    await db(env).update(tracks).set({ status: "retired" }).where(eq(tracks.id, retired.id));

    const diff = await json(await api(`/admin/packs/${pack.id}/diff`));
    expect(diff).toMatchObject({ currentVersion: 1, eligibleCount: 1, added: [], removed: [{ id: retired.id }] });

    await publish(pack.id);
    const v1 = packManifest.parse(await (await env.CLIPS.get("packs/all/v1/manifest.json"))!.json());
    const v2 = packManifest.parse(await (await env.CLIPS.get("packs/all/v2/manifest.json"))!.json());
    expect(v1.tracks.map((t) => t.id)).toEqual([stays.id, retired.id]);
    expect(v2.tracks.map((t) => t.id)).toEqual([stays.id]);
    const old = await env.DB.prepare("SELECT COUNT(*) AS c FROM pack_tracks pt JOIN pack_versions pv ON pv.id = pt.pack_version_id WHERE pv.version = 1").first<{ c: number }>();
    expect(old!.c).toBe(2);
  });

  it("reports added tracks in the diff before the first publish", async () => {
    const t = await eligible();
    const pack = await createPack();
    expect(await json(await api(`/admin/packs/${pack.id}/diff`))).toMatchObject({ currentVersion: null, added: [{ id: t.id }], removed: [] });
  });

  it("requires an admin sign-in", async () => {
    expect((await rawRequest("/admin/packs")).status).toBe(401);
  });
});

describe("GET /v1/packs", () => {
  it("lists only published packs at their current version, cached for 5 minutes", async () => {
    await eligible();
    const published = await createPack({ slug: "first" });
    await createPack({ slug: "unpublished" });
    await publish(published.id);
    const res = await rawRequest("/v1/packs");
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=300");
    const { packs } = await json(res);
    expect(packs).toHaveLength(1);
    expect(packs[0]).toMatchObject({
      slug: "first", names: { am: "ሁሉም", en: "Everything" }, version: 1, trackCount: 1,
      manifestUrl: `${env.CDN_BASE_URL}/packs/first/v1/manifest.json`,
    });
    expect(packs[0].totalBytes).toBeGreaterThan(0);
  });
});

describe("publishing safely", () => {
  /** env whose D1 runs `before` just ahead of the publish batch: a change landing between the read and the write. */
  const racing = (before: () => Promise<unknown>, fail = false) => {
    const real = env.DB;
    const DB = new Proxy(real, {
      get(target, prop) {
        if (prop === "batch") {
          return async (stmts: D1PreparedStatement[]) => {
            await before();
            if (fail) throw new Error("D1 overloaded");
            return target.batch(stmts);
          };
        }
        const v = Reflect.get(target, prop);
        return typeof v === "function" ? v.bind(target) : v;
      },
    });
    return { ...env, DB } as typeof env;
  };

  it("writes nothing, and removes its manifest, when a track is rejected mid-publish", async () => {
    const t = await eligible();
    const pack = await createPack();
    const e = racing(() => db(env).update(tracks).set({ status: "rejected" }).where(eq(tracks.id, t.id)));
    await expect(publishVersion(e, await requirePack(e, pack.id), undefined, null)).rejects.toMatchObject({ code: "catalog_changed" });
    expect(await env.CLIPS.head("packs/all/v1/manifest.json")).toBeNull();
    expect((await env.DB.prepare("SELECT COUNT(*) AS c FROM pack_versions").first<{ c: number }>())!.c).toBe(0);
    expect((await env.DB.prepare("SELECT current_version FROM packs").first<{ current_version: number | null }>())!.current_version).toBeNull();
  });

  it("does the same when a clip is recut mid-publish (new checksum)", async () => {
    const t = await eligible();
    const pack = await createPack();
    const e = racing(() => db(env).update(clips).set({ sha256: "f".repeat(64) }).where(eq(clips.trackId, t.id)));
    await expect(publishVersion(e, await requirePack(e, pack.id), undefined, null)).rejects.toMatchObject({ code: "catalog_changed" });
    expect(await env.CLIPS.head("packs/all/v1/manifest.json")).toBeNull();
  });

  it("removes its manifest when the batch fails, so the retry reuses the number", async () => {
    await eligible();
    const pack = await createPack();
    const e = racing(async () => undefined, true);
    await expect(publishVersion(e, await requirePack(e, pack.id), undefined, null)).rejects.toThrow("D1 overloaded");
    expect(await env.CLIPS.head("packs/all/v1/manifest.json")).toBeNull();
    expect((await json(await publish(pack.id))).published.version).toBe(1);
  });

  it("never moves current_version backwards", async () => {
    await eligible();
    const pack = await createPack();
    await publish(pack.id);
    // A faster, higher-numbered publish already went live.
    await env.DB.prepare("UPDATE packs SET current_version = 9 WHERE id = ?1").bind(pack.id).run();
    expect((await json(await publish(pack.id))).published.version).toBe(2);
    expect((await env.DB.prepare("SELECT current_version FROM packs").first<{ current_version: number }>())!.current_version).toBe(9);
  });

  it("answers a structured error when the manifest would be invalid, and writes nothing", async () => {
    await eligible();
    const pack = await createPack();
    const e = { ...env, CDN_BASE_URL: "not a url" } as typeof env;
    await expect(publishVersion(e, await requirePack(e, pack.id), undefined, null)).rejects.toMatchObject({ status: 500, code: "manifest_invalid" });
    expect((await env.CLIPS.list({ prefix: "packs/" })).objects).toHaveLength(0);
  });

  it("tells the confirm step the number it will really publish", async () => {
    await eligible();
    const pack = await createPack();
    await env.CLIPS.put("packs/all/v1/manifest.json", "stray");
    expect((await json(await api(`/admin/packs/${pack.id}/diff`))).nextVersion).toBe(2);
    expect((await json(await publish(pack.id))).published.version).toBe(2);
  });

  it("rejects a body that is not JSON", async () => {
    const pack = await createPack();
    const jwt = await signAccessJwt({ email: "admin@yz.test" });
    const res = await rawRequest(`/admin/packs/${pack.id}/versions`, { method: "POST", jwt, headers: { "content-type": "application/json" }, body: "{nope" });
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("invalid_json");
  });
});

describe("publishing what the confirm step showed", () => {
  it("publishes the diff's tracks, not ones approved after it was opened", async () => {
    const shown = await eligible();
    const pack = await createPack();
    const diff = await json(await api(`/admin/packs/${pack.id}/diff`));
    expect(diff.trackIds).toEqual([shown.id]);
    await eligible(); // approved while the confirm dialog was open
    const res = await publish(pack.id, { trackIds: diff.trackIds, expectedVersion: diff.nextVersion });
    expect(res.status).toBe(201);
    expect((await json(res)).published).toMatchObject({ version: 1, trackCount: 1 });
  });

  it("refuses when another publish took the version the confirm step named", async () => {
    await eligible();
    const pack = await createPack();
    const diff = await json(await api(`/admin/packs/${pack.id}/diff`));
    await publish(pack.id); // someone else published v1 first
    const res = await publish(pack.id, { trackIds: diff.trackIds, expectedVersion: diff.nextVersion });
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("version_conflict");
    expect((await env.CLIPS.list({ prefix: "packs/" })).objects.map((o) => o.key)).toEqual(["packs/all/v1/manifest.json"]);
  });
});
