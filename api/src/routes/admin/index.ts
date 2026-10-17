import { Hono } from "hono";
import type { AppEnv } from "../../env";
import { requireAdmin, requireService } from "../../lib/accessAuth";
import { analyticsRoutes } from "./analytics";
import { catalog } from "./catalog";
import { ingestRoutes } from "./ingest";
import { jobRoutes } from "./jobs";
import { packRoutes } from "./packs";
import { reportRoutes } from "./reports";
import { reviewRoutes } from "./reviewItems";
import { rollupRoutes } from "./rollups";
import { taxonomy } from "./taxonomy";

// Human-authenticated admin routes. The requireAdmin middleware guards every
// route registered here.
const human = new Hono<AppEnv>();
human.use("*", requireAdmin());

// Temporary: echoes the authenticated admin. Removed once real admin routes land.
human.get("/whoami", (c) => c.json({ admin: c.get("admin") }));
human.route("/", catalog);
human.route("/", jobRoutes);
human.route("/", packRoutes);
human.route("/", taxonomy);
human.route("/", reviewRoutes);
human.route("/", rollupRoutes);
human.route("/", reportRoutes);
human.route("/", analyticsRoutes);

// Service-token routes for GitHub Actions ingestion. requireService guards these.
const ingest = new Hono<AppEnv>();
ingest.use("*", requireService());
ingest.get("/whoami", (c) => c.json({ service: c.get("service") }));
ingest.route("/", ingestRoutes);

// Mount order matters: /ingest is registered before the catch-all human router
// so ingest requests pass through requireService only, and human requests
// through requireAdmin only (verified by test). No /admin route is reachable
// without one of the two middlewares.
export const admin = new Hono<AppEnv>();
admin.route("/ingest", ingest);
admin.route("/", human);
