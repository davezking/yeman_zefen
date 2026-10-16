// Player app API (/v1). Every route needs a Firebase ID token except the
// public reads in PUBLIC_ROUTES. Routes that also need a registered (non-
// anonymous) account add `requireUser({ allowAnonymous: false })`.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import { cdnUrl } from "../lib/cdn";
import { requireUser } from "../lib/firebaseAuth";
import { me } from "./me";
import { sessions } from "./v1/sessions";

export const v1 = new Hono<AppEnv>();

/** Paths (under /v1) that are public for GET (and HEAD). Everything else is authenticated. */
const PUBLIC_ROUTES = new Set(["/config", "/packs"]);

const authenticate = requireUser();
v1.use("*", async (c, next) => {
  const method = c.req.method;
  const sub = c.req.path.slice("/v1".length);
  if ((method === "GET" || method === "HEAD") && PUBLIC_ROUTES.has(sub)) return next();
  return authenticate(c, next);
});

v1.route("/me", me);
v1.route("/sessions", sessions);

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
