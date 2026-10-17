// The royalty usage report (FR-22): plays per track over a date range, from the nightly roll-up
// `royalty_daily`. Spec: docs/architecture.md §5 "Reports".
import { z } from "zod";
import { DAY_MS, MAX_RANGE_DAYS, checkRange, day } from "./dayRange";

/** Longest range one report covers, in days (the shared day-range limit). */
export const MAX_REPORT_DAYS = MAX_RANGE_DAYS;

export const reportQuery = z
  .object({
    from: day,
    to: day,
    format: z.enum(["json", "csv"]).default("json"),
  })
  .superRefine(checkRange);


export type RoyaltyRow = {
  trackId: number;
  titleAm: string | null;
  titleLatin: string | null;
  artistAm: string;
  artistLatin: string | null;
  album: string | null;
  releaseYear: number | null;
  plays: number;
};

/** One statement. Every royalty_daily row has a track and every track an artist (both are foreign keys), so no play is dropped by the joins. */
export const ROYALTY_SQL = `
  SELECT t.id AS trackId, t.title_am AS titleAm, t.title_latin AS titleLatin,
         a.name_am AS artistAm, a.name_latin AS artistLatin,
         t.album AS album, t.release_year AS releaseYear, SUM(r.plays) AS plays
    FROM royalty_daily r
    JOIN tracks t ON t.id = r.track_id
    JOIN artists a ON a.id = t.artist_id
   WHERE r.date >= ?1 AND r.date <= ?2
   GROUP BY r.track_id
   ORDER BY plays DESC, t.id ASC`;

/** The days in the range that have finished their roll-up. A day is done once it has its `sessions` metric, which the roll-up writes even for a day with no sessions (as `missingDates` in cron/rollups.ts reads it). */
export const ROLLED_UP_SQL = `
  SELECT DISTINCT date FROM analytics_daily
   WHERE metric = 'sessions' AND date >= ?1 AND date <= ?2`;

/**
 * The days from `from` to `to` that are not rolled up, oldest first: today, yesterday before the
 * 00:30 UTC run, a day whose run failed, or a day before roll-ups began. Their plays are missing
 * from the report, so a report that lists any is not final.
 */
export function missingDays(from: string, to: string, rolledUp: Iterable<string>): string[] {
  const done = new Set(rolledUp);
  const out: string[] = [];
  const end = Date.parse(`${to}T00:00:00Z`);
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= end; t += DAY_MS) {
    const d = new Date(t).toISOString().slice(0, 10);
    if (!done.has(d)) out.push(d);
  }
  return out;
}

export function totalPlays(rows: readonly RoyaltyRow[]): number {
  return rows.reduce((sum, r) => sum + r.plays, 0);
}

export const CSV_HEADER = [
  "Track ID",
  "Title (Amharic)",
  "Title (Latin)",
  "Artist (Amharic)",
  "Artist (Latin)",
  "Album",
  "Release year",
  "Plays",
] as const;

/**
 * One CSV cell. Quoted when it holds a comma, quote or line break. A text cell that starts with
 * `=`, `+`, `-` or `@` gets a leading apostrophe, so a title scraped from the web cannot run as a
 * formula when the association opens the file in Excel.
 */
export function csvCell(value: string | number | null): string {
  if (value === null) return "";
  let text = String(value);
  if (typeof value === "string" && /^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

/**
 * The report as CSV: UTF-8 with a byte order mark (so Excel reads Fidel correctly), a header row,
 * one row per track and a final `Total` row. Lines end in CRLF.
 */
export function royaltyCsv(rows: readonly RoyaltyRow[]): string {
  const lines = [
    CSV_HEADER.map(csvCell).join(","),
    ...rows.map((r) =>
      [r.trackId, r.titleAm, r.titleLatin, r.artistAm, r.artistLatin, r.album, r.releaseYear, r.plays].map(csvCell).join(","),
    ),
    ["Total", "", "", "", "", "", "", totalPlays(rows)].map(csvCell).join(","),
  ];
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

/** The download's name, with the range in it. A report with days missing says so in the name, so it is not sent on as final. */
export function reportFilename(from: string, to: string, partial = false): string {
  return `royalty-report-${from}_to_${to}${partial ? "-partial" : ""}.csv`;
}
