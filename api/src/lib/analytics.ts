// Core analytics (FR-23) for the admin dashboard, read from the nightly roll-ups.
// Spec: docs/architecture.md §5 "Reports". Retention is written by cron/rollups.ts.
import { UNKNOWN_COUNTRY } from "../cron/rollups";

export const METRICS_SQL = `
  SELECT date, metric, value FROM analytics_daily
   WHERE date >= ?1 AND date <= ?2 AND dimension = '' ORDER BY date`;

export const COUNTRIES_SQL = `
  SELECT dimension AS country, SUM(value) AS plays FROM analytics_daily
   WHERE metric = 'plays_by_country' AND date >= ?1 AND date <= ?2
   GROUP BY dimension ORDER BY plays DESC, dimension ASC`;

export const ADS_SQL = `
  SELECT date, format, event, SUM(count) AS count FROM ad_events_daily
   WHERE date >= ?1 AND date <= ?2 GROUP BY date, format, event ORDER BY date`;

export type DayStats = {
  date: string;
  /** False for a day with no roll-up yet (today, a failed run, before roll-ups began): its zeros are not real. */
  rolledUp: boolean;
  dau: number;
  /** Users created that day: the stand-in for installs, which the data does not have. */
  newUsers: number;
  sessions: number;
  rounds: number;
  /** Rounds per session, two decimals; 0 for a day with no sessions. */
  roundsPerSession: number;
  /** Cohort = users created this day. Counts of users who played N days later; null until that day is rolled up. */
  retained: { d1: number | null; d7: number | null; d30: number | null };
  interstitialsShown: number;
  rewardedCompleted: number;
};

export type MetricRow = { date: string; metric: string; value: number };
export type AdRow = { date: string; format: string; event: string; count: number };
export type CountryRow = { country: string; plays: number };

const DAY_MS = 86_400_000;

/** Every day from `from` to `to`, one entry each, in order, with what the roll-ups know. */
export function buildDays(from: string, to: string, metrics: MetricRow[], ads: AdRow[]): DayStats[] {
  const byDay = new Map<string, Map<string, number>>();
  for (const m of metrics) {
    if (!byDay.has(m.date)) byDay.set(m.date, new Map());
    byDay.get(m.date)!.set(m.metric, m.value);
  }
  const adCounts = new Map(ads.map((a) => [`${a.date}|${a.format}|${a.event}`, a.count]));
  const adAt = (date: string, format: string, event: string) => adCounts.get(`${date}|${format}|${event}`) ?? 0;
  const out: DayStats[] = [];
  const end = Date.parse(`${to}T00:00:00Z`);
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= end; t += DAY_MS) {
    const date = new Date(t).toISOString().slice(0, 10);
    const m = byDay.get(date);
    const get = (k: string) => m?.get(k) ?? 0;
    const retained = (k: string) => m?.get(k) ?? null;
    out.push({
      date,
      rolledUp: m?.has("sessions") ?? false,
      dau: get("dau"),
      newUsers: get("new_users"),
      sessions: get("sessions"),
      rounds: get("rounds"),
      // Stored x100 (an integer column), shown with two decimals.
      roundsPerSession: get("rounds_per_session") / 100,
      retained: { d1: retained("retention_d1"), d7: retained("retention_d7"), d30: retained("retention_d30") },
      interstitialsShown: adAt(date, "interstitial", "shown"),
      rewardedCompleted: adAt(date, "rewarded", "completed"),
    });
  }
  return out;
}

export type Countries = {
  /** Plays in countries Cloudflare placed (`XX` left out). */
  placed: number;
  /** Plays Cloudflare could not place. */
  unknown: number;
  /** Plays outside Ethiopia over plays in a known country; null with no placed plays. */
  diasporaShare: number | null;
  top: CountryRow[];
};

export const TOP_COUNTRIES = 10;

export function buildCountries(rows: CountryRow[]): Countries {
  const known = rows.filter((r) => r.country !== UNKNOWN_COUNTRY);
  const placed = known.reduce((n, r) => n + r.plays, 0);
  const et = known.find((r) => r.country === "ET")?.plays ?? 0;
  return {
    placed,
    unknown: rows.find((r) => r.country === UNKNOWN_COUNTRY)?.plays ?? 0,
    diasporaShare: placed === 0 ? null : (placed - et) / placed,
    top: known.slice(0, TOP_COUNTRIES),
  };
}
