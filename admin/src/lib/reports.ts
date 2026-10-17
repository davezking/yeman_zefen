// Date ranges for the royalty report. Days are UTC `YYYY-MM-DD`, the same days the nightly
// roll-up and the API use, so "last month" here is the month the Worker would count.

/** The API's limit on one report (api/src/lib/royaltyReport.ts). */
export const MAX_REPORT_DAYS = 366;
const DAY_MS = 86_400_000;

export type DayRange = { from: string; to: string };

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** True for a real calendar day written `YYYY-MM-DD`. */
export function isDay(s: string): boolean {
  if (!DAY_RE.test(s)) return false;
  const t = Date.parse(`${s}T00:00:00Z`);
  return !Number.isNaN(t) && new Date(t).toISOString().slice(0, 10) === s;
}

const day = (y: number, m: number, d: number): string => new Date(Date.UTC(y, m, d)).toISOString().slice(0, 10);

/** The calendar month before the one containing `now`. */
export function lastMonth(now: number): DayRange {
  const d = new Date(now);
  const y = d.getUTCFullYear();
  const m = d.getUTCMonth();
  return { from: day(y, m - 1, 1), to: day(y, m, 0) };
}

/** The calendar quarter (Jan–Mar, Apr–Jun, Jul–Sep, Oct–Dec) before the one containing `now`. */
export function lastQuarter(now: number): DayRange {
  const d = new Date(now);
  const y = d.getUTCFullYear();
  const startMonth = Math.floor(d.getUTCMonth() / 3) * 3;
  return { from: day(y, startMonth - 3, 1), to: day(y, startMonth, 0) };
}

/** Why the range cannot be reported, or null when it can. Matches the API's checks. */
export function rangeError(from: string, to: string): string | null {
  if (!isDay(from) || !isDay(to)) return "Pick a start and an end day.";
  if (from > to) return "The end day is before the start day.";
  const days = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS + 1;
  if (days > MAX_REPORT_DAYS) return `A report covers at most ${MAX_REPORT_DAYS} days.`;
  return null;
}

/** The download's name, as the Worker names it: `-partial` when days of the range are not rolled up. */
export const reportFilename = (r: DayRange, partial = false): string =>
  `royalty-report-${r.from}_to_${r.to}${partial ? "-partial" : ""}.csv`;

/** "2026-10-02", or "2026-10-02, 2026-10-03 and 4 more" for a long list. */
export function missingDaysText(days: readonly string[], show = 3): string {
  if (days.length <= show) return days.join(", ");
  return `${days.slice(0, show).join(", ")} and ${days.length - show} more`;
}
