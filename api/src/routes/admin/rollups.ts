// Re-run the nightly roll-up for one day (backfill, or after a fix). Spec: docs/architecture.md §6.
import { Hono } from "hono";
import { z } from "zod";
import { dayBounds, rollUpDay, utcDate } from "../../cron/rollups";
import type { AppEnv } from "../../env";
import { requireRole } from "../../lib/accessAuth";
import { ApiError } from "../../lib/errors";
import { parse, readJson } from "../../lib/validate";

export const rollupRoutes = new Hono<AppEnv>();

const body = z.object({ date: z.string() }).strict();

// POST /admin/rollups/run { date: "YYYY-MM-DD" }: replaces that day's roll-up rows and answers with
// the summary. Admins only. A day that has not finished (today or later, UTC) is refused: its rows
// would be wrong the moment another session arrived.
rollupRoutes.post("/rollups/run", requireRole("admin"), async (c) => {
  const { date } = parse(body, await readJson(c));
  if (!dayBounds(date)) throw new ApiError(400, "validation_error", "date: must be a real calendar day, YYYY-MM-DD");
  if (date >= utcDate(Date.now())) throw new ApiError(400, "validation_error", "date: that UTC day has not ended yet");
  return c.json({ rollup: await rollUpDay(c.env, date) });
});
