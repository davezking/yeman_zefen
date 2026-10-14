// The review queue: list and count review items, and close them. A track's own open items also come back in
// GET /admin/tracks/:id. Ingest only raises items about tracks, so the queue is the track items.
import { and, asc, eq, gt, notInArray, sql, type SQL } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db } from "../../db/client";
import { artists, OUT_OF_CATALOG, REVIEW_REASONS, REVIEW_STATUSES, reviewItems, tracks } from "../../db/schema";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { idParam, parse } from "../../lib/validate";

export const REVIEW_PAGE_SIZE = 50;

export const reviewRoutes = new Hono<AppEnv>();

const listQuerySchema = z.strictObject({
  reason: z.enum(REVIEW_REASONS).optional(),
  status: z.enum(REVIEW_STATUSES).default("open"),
  cursor: z.coerce.number().int().positive().optional(),
});
export type ReviewListFilters = z.infer<typeof listQuerySchema>;

/** Oldest first, keyset-paginated on id. Exported so tests can EXPLAIN the exact SQL. */
export function reviewListQuery(d: ReturnType<typeof db>, f: ReviewListFilters) {
  const where: (SQL | undefined)[] = [
    eq(reviewItems.entityType, "track"),
    eq(reviewItems.status, f.status),
    // A rejected or retired track has nothing left to review.
    notInArray(tracks.status, [...OUT_OF_CATALOG]),
  ];
  if (f.reason) where.push(eq(reviewItems.reason, f.reason));
  if (f.cursor) where.push(gt(reviewItems.id, f.cursor));
  return d
    .select({
      id: reviewItems.id,
      reason: reviewItems.reason,
      status: reviewItems.status,
      detailsJson: reviewItems.detailsJson,
      track: {
        id: tracks.id,
        titleAm: tracks.titleAm,
        titleLatin: tracks.titleLatin,
        releaseYear: tracks.releaseYear,
        generationId: tracks.generationId,
        status: tracks.status,
        durationMs: tracks.durationMs,
        sourceUrl: tracks.sourceUrl,
        artistId: tracks.artistId,
        artistNameAm: artists.nameAm,
        artistNameLatin: artists.nameLatin,
      },
    })
    .from(reviewItems)
    .innerJoin(tracks, eq(tracks.id, reviewItems.entityId))
    .innerJoin(artists, eq(artists.id, tracks.artistId))
    .where(and(...where))
    .orderBy(asc(reviewItems.id))
    .limit(REVIEW_PAGE_SIZE + 1);
}

/** `details_json` is free-form text written by the scraper and the cutter; hand it on parsed, or null if it is not JSON. */
function parseDetails(json: string | null): unknown {
  if (json === null) return null;
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
}

reviewRoutes.get("/review-items", async (c) => {
  const filters = parse(listQuerySchema, c.req.query(), "query");
  const rows = await reviewListQuery(db(c.env), filters);
  const page = rows.slice(0, REVIEW_PAGE_SIZE);
  const items = page.map(({ detailsJson, ...item }) => ({ ...item, details: parseDetails(detailsJson) }));
  const nextCursor = rows.length > REVIEW_PAGE_SIZE ? String(page[page.length - 1]!.id) : null;
  return c.json({ items, nextCursor });
});

// Registered before "/review-items/:id/..." routes; "counts" is not an id.
reviewRoutes.get("/review-items/counts", async (c) => {
  const rows = await db(c.env)
    .select({ reason: reviewItems.reason, n: sql<number>`COUNT(*)` })
    .from(reviewItems)
    // The same joins as the list, so a badge never counts an item the list cannot show.
    .innerJoin(tracks, eq(tracks.id, reviewItems.entityId))
    .innerJoin(artists, eq(artists.id, tracks.artistId))
    .where(and(eq(reviewItems.entityType, "track"), eq(reviewItems.status, "open"), notInArray(tracks.status, [...OUT_OF_CATALOG])))
    .groupBy(reviewItems.reason);
  const counts = Object.fromEntries(REVIEW_REASONS.map((r) => [r, 0])) as Record<(typeof REVIEW_REASONS)[number], number>;
  for (const r of rows) counts[r.reason] = r.n;
  return c.json({ counts });
});

function close(status: "resolved" | "dismissed") {
  return async (c: import("hono").Context<AppEnv>) => {
    const d = db(c.env);
    const id = idParam(c);
    const admin = c.get("admin");
    // The status guard makes this race-safe: of two admins closing the same item, one gets the 409.
    const [item] = await d
      .update(reviewItems)
      .set({ status, resolvedBy: admin?.email ?? null, resolvedAt: Date.now() })
      .where(and(eq(reviewItems.id, id), eq(reviewItems.status, "open")))
      .returning();
    if (!item) {
      const existing = await d.select().from(reviewItems).where(eq(reviewItems.id, id)).get();
      if (!existing) throw new ApiError(404, "not_found", `Review item ${id} not found`);
      throw new ApiError(409, "already_closed", `Review item ${id} is already ${existing.status}`);
    }
    return c.json({ item });
  };
}

reviewRoutes.post("/review-items/:id/resolve", close("resolved"));
reviewRoutes.post("/review-items/:id/dismiss", close("dismissed"));
