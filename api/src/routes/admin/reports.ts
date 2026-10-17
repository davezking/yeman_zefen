// Reports for admins. The royalty report is the usage count the music association is sent.
// Spec: docs/architecture.md §5 "Reports".
import { Hono } from "hono";
import type { AppEnv } from "../../env";
import { utcDate } from "../../cron/rollups";
import { requireRole } from "../../lib/accessAuth";
import {
  ROLLED_UP_SQL,
  ROYALTY_SQL,
  missingDays,
  reportFilename,
  reportQuery,
  royaltyCsv,
  totalPlays,
  type RoyaltyRow,
} from "../../lib/royaltyReport";
import { parse } from "../../lib/validate";

export const reportRoutes = new Hono<AppEnv>();

// GET /admin/reports/royalty?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv: plays per track over the
// range (both days included), most played first, with the total. Admins only: it is the figure the
// association is paid against. A day only counts once its nightly roll-up has run (today, yesterday
// before 00:30 UTC, or a day whose run failed do not), so `missingDays` lists the days in the range
// that are not final, `includesToday` says whether today is one, and a CSV with days missing is
// named `-partial`.
reportRoutes.get("/reports/royalty", requireRole("admin"), async (c) => {
  const { from, to, format } = parse(reportQuery, c.req.query(), "query");
  // One batch, so the plays and the list of finished days are read together.
  const [plays, rolledUp] = await c.env.DB.batch([
    c.env.DB.prepare(ROYALTY_SQL).bind(from, to),
    c.env.DB.prepare(ROLLED_UP_SQL).bind(from, to),
  ]);
  const results = plays!.results as RoyaltyRow[];
  const missing = missingDays(from, to, (rolledUp!.results as { date: string }[]).map((r) => r.date));

  if (format === "csv") {
    return new Response(royaltyCsv(results), {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="${reportFilename(from, to, missing.length > 0)}"`,
        "cache-control": "no-store",
      },
    });
  }
  return c.json({
    from,
    to,
    includesToday: to >= utcDate(Date.now()),
    missingDays: missing,
    totalPlays: totalPlays(results),
    rows: results,
  });
});
