// Pure helpers for the moderation pages: the note rule, labels, and the response-time histogram.

export const NOTE_MAX = 500;

/** Why a note cannot be sent, or null. The Worker enforces the same rule. */
export function noteProblem(note: string): string | null {
  const text = note.trim();
  if (text === "") return "A note is required.";
  if (text.length > NOTE_MAX) return `At most ${NOTE_MAX} characters (this is ${text.length}).`;
  return null;
}

const RULE_LABELS: Record<string, string> = {
  inhuman_accuracy: "Near-perfect accuracy with instant answers",
  bot_regularity: "Bot-like response timing",
  session_flood: "Too many sessions in an hour",
  weekly_outlier: "Runaway weekly leader",
};

const FLAG_LABELS: Record<string, string> = {
  fast_response: "Answers too fast",
  late_answer: "Answer after the window",
  duration_mismatch: "Durations do not add up",
  clock_out_of_range: "Device clock out of range",
  era_mismatch: "Era does not match",
  catalog_mismatch: "Options not in the catalog",
  voided: "Voided by an admin",
};

export const ruleLabel = (rule: string) => RULE_LABELS[rule] ?? rule;

/** The labels for a session's comma-separated flag reasons. */
export const flagLabels = (reason: string | null): string[] => (reason ? reason.split(",").map((r) => FLAG_LABELS[r] ?? r) : []);

/** The rules the nightly pass raised, across every day it added evidence for the flag (first seen first). */
export function anomalyRules(details: unknown): string[] {
  const days = (details as { days?: Record<string, { rules?: unknown }> } | null)?.days;
  if (!days || typeof days !== "object") return [];
  const rules = new Set<string>();
  for (const date of Object.keys(days).sort()) {
    const list = days[date]?.rules;
    if (Array.isArray(list)) for (const r of list) if (typeof r === "string") rules.add(r);
  }
  return [...rules];
}

/** The days a flag has evidence for, oldest first, with the metrics that day. */
export function anomalyDays(details: unknown): { date: string; metrics: Record<string, unknown> }[] {
  const days = (details as { days?: Record<string, Record<string, unknown>> } | null)?.days;
  if (!days || typeof days !== "object") return [];
  return Object.keys(days).sort().map((date) => ({ date, metrics: days[date] ?? {} }));
}

/** What players reported about a display name (`name_report` details, see api routes/v1/reports.ts). */
export type NameReport = { reportedName: string | null; reports: number; reporters: number; lastReportedAt: number | null };

export function nameReportDetails(details: unknown): NameReport {
  const d = (details && typeof details === "object" ? details : {}) as Record<string, unknown>;
  return {
    reportedName: typeof d.displayName === "string" ? d.displayName : null,
    reports: typeof d.reports === "number" ? d.reports : 0,
    reporters: Array.isArray(d.reporters) ? d.reporters.length : 0,
    lastReportedAt: typeof d.lastReportedAt === "number" ? d.lastReportedAt : null,
  };
}

export const BUCKET_MS = 500;
export const BUCKETS = 20;

export type Bucket = { label: string; count: number };

const seconds = (ms: number) => (ms / 1000).toFixed(1);

/** Response times in 0.5 s buckets up to 10 s, then one bucket for everything slower. Null times (no answer) are left out. */
export function responseHistogram(times: readonly (number | null)[]): Bucket[] {
  const buckets: Bucket[] = Array.from({ length: BUCKETS + 1 }, (_, i) => ({
    label: i < BUCKETS ? `${seconds(i * BUCKET_MS)}–${seconds((i + 1) * BUCKET_MS)} s` : `${seconds(BUCKETS * BUCKET_MS)} s+`,
    count: 0,
  }));
  for (const t of times) {
    if (t === null || !Number.isFinite(t) || t < 0) continue;
    buckets[Math.min(BUCKETS, Math.floor(t / BUCKET_MS))]!.count++;
  }
  return buckets;
}

/** The median of the numbers, or null when there are none. */
export function median(values: readonly number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
}
