// Reports for admins. The royalty report is the usage count the music association is sent.
// Spec: docs/architecture.md §5 "Reports".
import { Hono } from "hono";
import type { AppEnv } from "../../env";
import { utcDate } from "../../cron/rollups";
import { requireRole } from "../../lib/accessAuth";
import { ROYALTY_SQL, reportFilename, reportQuery, royaltyCsv, totalPlays, type RoyaltyRow } from "../../lib/royaltyReport";
import { parse } from "../../lib/validate";

export const reportRoutes = new Hono<AppEnv>();

// GET /admin/reports/royalty?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv: plays per track over the
// range (both days included), most played first, with the total. Admins only: it is the figure the
// association is paid against. Today (UTC) is not rolled up until tomorrow's run, so a range that
// includes it is short by today's plays; `includesToday` says so, and the page warns.
reportRoutes.get("/reports/royalty", requireRole("admin"), async (c) => {
  const { from, to, format } = parse(reportQuery, c.req.query(), "query");
  const { results } = await c.env.DB.prepare(ROYALTY_SQL).bind(from, to).all<RoyaltyRow>();

  if (format === "csv") {
    return new Response(royaltyCsv(results), {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="${reportFilename(from, to)}"`,
        "cache-control": "no-store",
      },
    });
  }
  return c.json({ from, to, includesToday: to >= utcDate(Date.now()), totalPlays: totalPlays(results), rows: results });
});
