export type JobStatus = "queued" | "running" | "succeeded" | "failed";

export const isActive = (status: string) => status === "queued" || status === "running";

/** "42 s", "3 min 05 s"; empty when the job has not started, "running" time counts up to `now`. */
export function duration(startedAt: number | null, finishedAt: number | null, now: number): string {
  if (startedAt === null) return "–";
  const s = Math.max(0, Math.round(((finishedAt ?? now) - startedAt) / 1000));
  return s < 60 ? `${s} s` : `${Math.floor(s / 60)} min ${String(s % 60).padStart(2, "0")} s`;
}

const COUNTS = ["tracks", "scraped", "created", "updated", "unchanged", "flagged", "durations", "errors"] as const;

/** One line for the table: the counts a run reported, or its error. `summary` is whatever JSON the run stored. */
export function summaryText(summary: unknown): string {
  if (summary === null || typeof summary !== "object") return "";
  const s = summary as Record<string, unknown>;
  const parts = COUNTS.filter((k) => typeof s[k] === "number").map((k) => `${k} ${s[k]}`);
  if (typeof s.error === "string") parts.unshift(`error: ${s.error}`);
  return parts.join(", ");
}

/** The first few error messages a run kept, for the details view. */
export function errorList(summary: unknown): string[] {
  const e = summary && typeof summary === "object" ? (summary as Record<string, unknown>).errors : undefined;
  return Array.isArray(e) ? e.filter((x): x is string => typeof x === "string").slice(0, 20) : [];
}

export const paramsText = (params: unknown): string =>
  params && typeof params === "object" && Object.keys(params).length > 0 ? JSON.stringify(params) : "";
