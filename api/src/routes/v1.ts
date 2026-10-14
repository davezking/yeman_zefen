// Public app API (/v1). No auth yet.
// TODO(phase 3): add the Firebase auth middleware to the player routes. /v1/packs may stay public.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import { cdnUrl } from "../lib/cdn";

export const v1 = new Hono<AppEnv>();

// Published packs at their current version. The app downloads each manifest from `manifestUrl`.
v1.get("/packs", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT p.slug, p.name_am, p.name_en, p.generation_id, p.genre_id,
            pv.version, pv.manifest_key, pv.track_count, pv.total_bytes, pv.published_at
       FROM packs p JOIN pack_versions pv ON pv.pack_id = p.id AND pv.version = p.current_version
      ORDER BY p.slug`,
  ).all<{
    slug: string; name_am: string; name_en: string; generation_id: number | null; genre_id: number | null;
    version: number; manifest_key: string; track_count: number; total_bytes: number; published_at: number;
  }>();
  c.header("Cache-Control", "public, max-age=300");
  return c.json({
    packs: results.map((r) => ({
      slug: r.slug,
      names: { am: r.name_am, en: r.name_en },
      generationId: r.generation_id,
      genreId: r.genre_id,
      version: r.version,
      manifestUrl: cdnUrl(c.env.CDN_BASE_URL, r.manifest_key),
      trackCount: r.track_count,
      totalBytes: r.total_bytes,
      publishedAt: r.published_at,
    })),
  });
});
