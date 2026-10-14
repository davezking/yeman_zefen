// Closing review items. Listing the queue is the review-queue page's job; a track's own open items
// already come back in GET /admin/tracks/:id.
import { and, eq } from "drizzle-orm";
import { Hono } from "hono";
import { db } from "../../db/client";
import { reviewItems } from "../../db/schema";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { idParam } from "../../lib/validate";

export const reviewRoutes = new Hono<AppEnv>();

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
