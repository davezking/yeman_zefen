// The analytics dashboard's sums: KPIs against the PRD targets and retention by cohort week.
// The Worker (api/src/lib/analytics.ts) sends per-day roll-up values; shares are worked out here.
import type { DayStats } from "../api/analytics";
import type { DayRange } from "./reports";

const DAY_MS = 86_400_000;

/** PRD targets (FR-23). */
export const TARGETS = { d1: 0.35, d7: 0.15, d30: 0.06, dau: 1000, roundsPerSession: 15 } as const;

export type KpiStatus = "met" | "missed" | "unknown";

export type Kpi = {
  key: "d1" | "d7" | "d30" | "dau" | "roundsPerSession";
  label: string;
  /** The measured value, or null when the range has nothing to measure it from. */
  value: number | null;
  target: number;
  /** Shown as a percentage; the others as a plain number. */
  percent: boolean;
  /** What the value is taken over, in words. */
  basis: string;
  status: KpiStatus;
};

const status = (value: number | null, target: number): KpiStatus => (value === null ? "unknown" : value >= target ? "met" : "missed");

/** The `days` that are final: those with a roll-up. */
const rolled = (days: readonly DayStats[]) => days.filter((d) => d.rolledUp);

/**
 * Retention over the range's cohorts: users who came back over users created, counting only the
 * cohorts whose answer is known (a cohort's D7 is not known until a week after it) and whose own day
 * is rolled up (otherwise its new_users, the denominator, is unknown). Null with none.
 */
export function overallRetention(days: readonly DayStats[], k: "d1" | "d7" | "d30"): number | null {
  let back = 0;
  let cohort = 0;
  for (const d of days) {
    const r = d.retained[k];
    if (r === null || !d.rolledUp) continue;
    back += r;
    cohort += d.newUsers;
  }
  return cohort === 0 ? null : back / cohort;
}

export function kpis(days: readonly DayStats[]): Kpi[] {
  const done = rolled(days);
  const latest = done.at(-1);
  const sessions = done.reduce((n, d) => n + d.sessions, 0);
  const rounds = done.reduce((n, d) => n + d.rounds, 0);
  const rps = sessions === 0 ? null : rounds / sessions;
  const dau = latest ? latest.dau : null;
  const list: Omit<Kpi, "status">[] = [
    { key: "d1", label: "D1 retention", value: overallRetention(days, "d1"), target: TARGETS.d1, percent: true, basis: "new users who played the next day" },
    { key: "d7", label: "D7 retention", value: overallRetention(days, "d7"), target: TARGETS.d7, percent: true, basis: "new users who played 7 days later" },
    { key: "d30", label: "D30 retention", value: overallRetention(days, "d30"), target: TARGETS.d30, percent: true, basis: "new users who played 30 days later" },
    { key: "dau", label: "Daily active users", value: dau, target: TARGETS.dau, percent: false, basis: latest ? `on ${latest.date}, the latest rolled-up day` : "no rolled-up day in the range" },
    { key: "roundsPerSession", label: "Rounds per session", value: rps, target: TARGETS.roundsPerSession, percent: false, basis: "all rounds over all sessions in the range" },
  ];
  return list.map((k) => ({ ...k, status: status(k.value, k.target) }));
}

/** The Monday (UTC) of the week containing `date`, as `YYYY-MM-DD`. */
export function weekStart(date: string): string {
  const t = Date.parse(`${date}T00:00:00Z`);
  const sinceMonday = (new Date(t).getUTCDay() + 6) % 7;
  return new Date(t - sinceMonday * DAY_MS).toISOString().slice(0, 10);
}

export type WeekRow = {
  /** Monday of the cohort week. */
  week: string;
  /** Days of the week inside the range: fewer than 7 at the range's ends. */
  days: number;
  newUsers: number;
  /** Retention of the week's cohorts; null when no day of the week has the answer yet. */
  d1: number | null;
  d7: number | null;
  d30: number | null;
};

/**
 * Cohorts grouped by the week they were created in, oldest first. Only days inside the range count,
 * so the first and last weeks can be partial (`days` < 7). A week's D7 only uses the cohort days that have it.
 */
export function retentionByWeek(days: readonly DayStats[]): WeekRow[] {
  const weeks = new Map<string, DayStats[]>();
  for (const d of days) {
    const w = weekStart(d.date);
    weeks.set(w, [...(weeks.get(w) ?? []), d]);
  }
  return [...weeks.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([week, list]) => ({
      week,
      days: list.length,
      newUsers: list.reduce((n, d) => n + d.newUsers, 0),
      d1: overallRetention(list, "d1"),
      d7: overallRetention(list, "d7"),
      d30: overallRetention(list, "d30"),
    }));
}

/** The default range: the 30 days ending yesterday (today is not rolled up until 00:30 UTC tomorrow). */
export function lastDays(now: number, n: number): DayRange {
  const day = (t: number) => new Date(t).toISOString().slice(0, 10);
  const yesterday = Math.floor(now / DAY_MS) * DAY_MS - DAY_MS;
  return { from: day(yesterday - (n - 1) * DAY_MS), to: day(yesterday) };
}

/** Chart axis label for a day: MM-DD, or the full day when the range spans more than one year. */
export const axisLabel = (date: string, range: DayRange) => (range.from.slice(0, 4) === range.to.slice(0, 4) ? date.slice(5) : date);

export const percent = (v: number | null, digits = 1) => (v === null ? "–" : `${(v * 100).toFixed(digits)} %`);
