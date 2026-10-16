// Leaderboard periods: `all`, or the ISO 8601 week of a UTC instant, such as `2026-W42`.

export const ALL_TIME = "all";

const DAY_MS = 86_400_000;

/** The ISO week (`YYYY-Www`, UTC) that `ms` falls in. Weeks start on Monday; week 1 holds the year's first Thursday. */
export function isoWeek(ms: number): string {
  const d = new Date(ms);
  const weekday = d.getUTCDay() || 7; // Monday = 1 … Sunday = 7
  // The Thursday of this week decides the week-numbering year.
  const thursday = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 4 - weekday);
  const year = new Date(thursday).getUTCFullYear();
  const week = Math.floor((thursday - Date.UTC(year, 0, 1)) / DAY_MS / 7) + 1;
  return `${year}-W${String(week).padStart(2, "0")}`;
}
