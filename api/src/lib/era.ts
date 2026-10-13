/** A generation's year range. A NULL end is open: `yearFrom: null` is "up to yearTo", `yearTo: null` is "from yearFrom on". */
export type EraRange = { id: number; yearFrom: number | null; yearTo: number | null };

/**
 * The generation whose range contains `year`, or null when there is no year or no range matches.
 * Ranges are expected not to overlap; if they do, the first one in `generations` wins, so pass
 * them in a stable order (generations are read ORDER BY sort).
 */
export function assignGeneration<T extends EraRange>(year: number | null, generations: readonly T[]): T | null {
  if (year === null) return null;
  return generations.find((g) => (g.yearFrom === null || year >= g.yearFrom) && (g.yearTo === null || year <= g.yearTo)) ?? null;
}
