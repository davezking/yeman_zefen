// Core analytics for the admin dashboard (FR-23). Any admin user may read it.
import { Hono } from "hono";
import type { AppEnv } from "../../env";
import {
  ADS_SQL,
  COUNTRIES_SQL,
  METRICS_SQL,
  buildCountries,
  buildDays,
  type AdRow,
  type CountryRow,
  type MetricRow,
} from "../../lib/analytics";
import { rangeQuery } from "../../lib/royaltyReport";
import { parse } from "../../lib/validate";

export const analyticsRoutes = new Hono<AppEnv>();

// GET /admin/analytics?from=YYYY-MM-DD&to=YYYY-MM-DD: one entry per day in the range (both included)
// with that day's roll-up, the plays by country over the range, and the day's ad counts. A day with
// `rolledUp: false` has no roll-up yet, so its zeros mean "unknown". Three D1 queries in one batch.
analyticsRoutes.get("/analytics", async (c) => {
  const { from, to } = parse(rangeQuery, c.req.query(), "query");
  const [metrics, countries, ads] = await c.env.DB.batch([
    c.env.DB.prepare(METRICS_SQL).bind(from, to),
    c.env.DB.prepare(COUNTRIES_SQL).bind(from, to),
    c.env.DB.prepare(ADS_SQL).bind(from, to),
  ]);
  return c.json({
    from,
    to,
    days: buildDays(from, to, metrics!.results as MetricRow[], ads!.results as AdRow[]),
    countries: buildCountries(countries!.results as CountryRow[]),
  });
});
