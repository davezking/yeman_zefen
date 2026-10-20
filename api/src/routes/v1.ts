// Player app API (/v1). Every route needs a Firebase ID token except the
// public reads in PUBLIC_ROUTES. Routes that also need a registered (non-
// anonymous) account add `requireUser({ allowAnonymous: false })`.
import { Hono } from "hono";
import type { AppEnv } from "../env";
import { cdnUrl } from "../lib/cdn";
import { remoteConfig } from "../lib/remoteConfig";
import { requireUser } from "../lib/firebaseAuth";
import { ipRateLimit, uidRateLimit } from "../lib/rateLimit";
import { me } from "./me";
import { leaderboard } from "./v1/leaderboard";
import { reports } from "./v1/reports";
import { sessions } from "./v1/sessions";

export const v1 = new Hono<AppEnv>();

/** Paths (under /v1) that are public for GET (and HEAD). Everything else is authenticated. */
const PUBLIC_ROUTES = new Set(["/config", "/packs"]);

// Per IP, before anything else: it also covers the public reads and bad tokens.
v1.use("*", ipRateLimit());

const authenticate = requireUser();
v1.use("*", async (c, next) => {
  const method = c.req.method;
  const sub = c.req.path.slice("/v1".length);
  if ((method === "GET" || method === "HEAD") && PUBLIC_ROUTES.has(sub)) return next();
  return authenticate(c, next);
});

// Per player, once the token is verified. Clip reports keep their own daily counter (routes/v1/reports.ts).
v1.use("/sessions", uidRateLimit("sessions", (m) => m === "POST"));
v1.use("/me/merge", uidRateLimit("merge", (m) => m === "POST"));
v1.use("/me", uidRateLimit("me", (m) => m === "PUT"));

v1.route("/me", me);
v1.route("/sessions", sessions);
v1.route("/leaderboard", leaderboard);
v1.route("/reports", reports);

// Tunables for the app (public, see PUBLIC_ROUTES). Cached for 10 minutes at the edge and in the app.
v1.get("/config", (c) => {
  // Read first: a config_invalid 500 must not carry the cache header.
  const config = remoteConfig(c.env);
  c.header("Cache-Control", "public, max-age=600");
  return c.json(config);
});

export const PACKS_SQL = `
  SELECT p.slug, p.name_am, p.name_en, p.generation_id, p.genre_id,
         pv.version, pv.manifest_key, pv.track_count, pv.total_bytes, pv.published_at
    FROM packs p JOIN pack_versions pv ON pv.pack_id = p.id AND pv.version = p.current_version
   ORDER BY p.slug`;

// Published packs at their current version. The app downloads each manifest from `manifestUrl`.
v1.get("/packs", async (c) => {
  const { results } = await c.env.DB.prepare(PACKS_SQL).all<{
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
