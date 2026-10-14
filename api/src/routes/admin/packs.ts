// Pack admin API: create a pack, list packs with their version history, preview and publish a version.
// Spec: docs/phase-1-sprint-3-prompts.md "Pack builder"; manifest contract: docs/pack-manifest.md.
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../../env";
import { cdnUrl } from "../../lib/cdn";
import { isUniqueViolation } from "../../lib/dbErrors";
import { ApiError } from "../../lib/errors";
import { diffAgainstCurrent, ELIGIBLE_JOINS, eligibleWhere, publishVersion, requirePack } from "../../lib/packs";
import { idParam, parse, readJson, readOptionalJson } from "../../lib/validate";

export const packRoutes = new Hono<AppEnv>();

const createSchema = z.strictObject({
  slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, "lowercase letters, digits and single dashes").max(60),
  nameAm: z.string().trim().min(1).max(120),
  nameEn: z.string().trim().min(1).max(120),
  generationId: z.number().int().positive().nullable().optional(),
  genreId: z.number().int().positive().nullable().optional(),
});

packRoutes.post("/packs", async (c) => {
  const b = parse(createSchema, await readJson(c));
  const refs: [string, number | null | undefined, string][] = [
    ["generationId", b.generationId, "generations"],
    ["genreId", b.genreId, "genres"],
  ];
  for (const [field, id, table] of refs) {
    if (id != null && !(await c.env.DB.prepare(`SELECT 1 AS x FROM ${table} WHERE id = ?1`).bind(id).first())) {
      throw new ApiError(400, "validation_error", `${field}: no such ${table.slice(0, -1)}`);
    }
  }
  try {
    const row = await c.env.DB.prepare(
      "INSERT INTO packs (slug, name_am, name_en, generation_id, genre_id) VALUES (?1, ?2, ?3, ?4, ?5) RETURNING id",
    )
      .bind(b.slug, b.nameAm, b.nameEn, b.generationId ?? null, b.genreId ?? null)
      .first<{ id: number }>();
    return c.json({ pack: await packOut(c.env, row!.id) }, 201);
  } catch (err) {
    if (isUniqueViolation(err)) throw new ApiError(409, "slug_taken", `A pack with slug '${b.slug}' exists`);
    throw err;
  }
});

type VersionRow = { pack_id: number; version: number; manifest_key: string; track_count: number; total_bytes: number; published_at: number; published_by: string | null };

const PACKS_SQL = `
  SELECT p.*, (SELECT COUNT(*) FROM tracks t ${ELIGIBLE_JOINS} WHERE ${eligibleWhere("p.generation_id", "p.genre_id")}) AS eligible_count
  FROM packs p`;

/** Packs (optionally just one) with their version history, newest version first. Two statements, however many packs. */
async function listPacks(env: AppEnv["Bindings"], onlyId?: number) {
  const [packs, versions] = await Promise.all([
    env.DB.prepare(`${PACKS_SQL} WHERE (?1 IS NULL OR p.id = ?1) ORDER BY p.id DESC`).bind(onlyId ?? null).all<PackRowWithCount>(),
    env.DB.prepare("SELECT * FROM pack_versions WHERE (?1 IS NULL OR pack_id = ?1) ORDER BY pack_id, version DESC").bind(onlyId ?? null).all<VersionRow>(),
  ]);
  return packs.results.map((p) => ({
    id: p.id,
    slug: p.slug,
    nameAm: p.name_am,
    nameEn: p.name_en,
    generationId: p.generation_id,
    genreId: p.genre_id,
    currentVersion: p.current_version,
    eligibleCount: p.eligible_count,
    versions: versions.results
      .filter((v) => v.pack_id === p.id)
      .map((v) => ({
        version: v.version,
        manifestUrl: cdnUrl(env.CDN_BASE_URL, v.manifest_key),
        trackCount: v.track_count,
        totalBytes: v.total_bytes,
        publishedAt: v.published_at,
        publishedBy: v.published_by,
      })),
  }));
}
type PackRowWithCount = Awaited<ReturnType<typeof requirePack>> & { eligible_count: number };

async function packOut(env: AppEnv["Bindings"], id: number) {
  return (await listPacks(env, id))[0]!;
}

packRoutes.get("/packs", async (c) => c.json({ items: await listPacks(c.env) }));

// What publishing now would change against the current version: the confirm step shows this.
packRoutes.get("/packs/:id/diff", async (c) => c.json(await diffAgainstCurrent(c.env, await requirePack(c.env, idParam(c)))));

const publishSchema = z.strictObject({
  trackIds: z.array(z.number().int().positive()).min(1).max(10_000).optional(),
  /** The version the confirm step showed (`nextVersion` from the diff). If another publish took it, 409. */
  expectedVersion: z.number().int().positive().optional(),
});

packRoutes.post("/packs/:id/versions", async (c) => {
  const pack = await requirePack(c.env, idParam(c));
  // No body means "all eligible tracks".
  const body = parse(publishSchema, await readOptionalJson(c));
  const published = await publishVersion(c.env, pack, body.trackIds, c.get("admin")?.email ?? null, body.expectedVersion);
  return c.json({ published }, 201);
});
