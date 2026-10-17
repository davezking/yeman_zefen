// A from/to range of UTC days (`YYYY-MM-DD`, both included), as the report and analytics endpoints take it.
import { z } from "zod";

/** Longest range one request covers, in days: a year, plus a leap day. */
export const MAX_RANGE_DAYS = 366;
export const DAY_MS = 86_400_000;

/** `YYYY-MM-DD` for the UTC day containing `ms`. */
export function utcDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** [start, end) of a UTC day in epoch ms, or null when `date` is not a real calendar day. */
export function dayBounds(date: string): { start: number; end: number } | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const start = Date.parse(`${date}T00:00:00.000Z`);
  if (Number.isNaN(start) || utcDate(start) !== date) return null;
  return { start, end: start + DAY_MS };
}

export const day = z.string().refine((s) => dayBounds(s) !== null, "must be a real calendar day, YYYY-MM-DD");

/** Days from `from` to `to`, both included. */
export function rangeDays(from: string, to: string): number {
  return (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS + 1;
}

/** `to` must not be before `from`, and the range is at most MAX_RANGE_DAYS. Skipped while either day is invalid (their own errors say why). */
export function checkRange(q: { from: string; to: string }, ctx: z.RefinementCtx): void {
  if (dayBounds(q.from) === null || dayBounds(q.to) === null) return;
  if (q.from > q.to) {
    ctx.addIssue({ code: "custom", path: ["to"], message: "must not be before from" });
  } else if (rangeDays(q.from, q.to) > MAX_RANGE_DAYS) {
    ctx.addIssue({ code: "custom", path: ["to"], message: `the range is at most ${MAX_RANGE_DAYS} days` });
  }
}

export const rangeQuery = z.object({ from: day, to: day }).superRefine(checkRange);
