// What the review queue needs to know about review items, kept apart from the UI so it can be tested.
import { z } from "zod";

export const REASONS = ["translit_uncertain", "possible_duplicate", "era_unknown", "missing_audio", "short_audio"] as const;
export type Reason = (typeof REASONS)[number];

/** One label per reason, used for the queue's tabs and for a track's open items. */
export const REASON_LABEL: Record<Reason, string> = {
  translit_uncertain: "Spelling uncertain",
  possible_duplicate: "Possible duplicate",
  era_unknown: "Era unknown",
  missing_audio: "Missing audio",
  short_audio: "Short audio",
};

export const isReason = (v: string | null): v is Reason => REASONS.some((r) => r === v);

// ---------------------------------------------------------------- details
// `details` is free-form JSON from the scraper and the cutter. Each reason has a shape it is expected to have; a
// shape that does not match is treated as "no details" rather than breaking the panel.

const translitSchema = z.object({
  field: z.enum(["artist", "title"]),
  source: z.string(),
  generated: z.string(),
  confidence: z.number().optional(),
  distance: z.number().optional(),
});
export type TranslitDetails = z.infer<typeof translitSchema>;

const candidateSchema = z.object({
  /** A catalog id. A candidate from the same scrape batch has only a source URL until it is ingested. */
  id: z.number().int().positive().optional(),
  sourceUrl: z.string().optional(),
  score: z.number().optional(),
  durationDiff: z.number().optional(),
});
export type Candidate = z.infer<typeof candidateSchema>;

const duplicateSchema = z.object({
  field: z.enum(["artist", "track"]),
  candidates: z.array(candidateSchema),
  variant_of: z.string().optional(),
});
export type DuplicateDetails = z.infer<typeof duplicateSchema>;

export const parseTranslit = (d: unknown): TranslitDetails | null => translitSchema.safeParse(d).data ?? null;
export const parseDuplicate = (d: unknown): DuplicateDetails | null => duplicateSchema.safeParse(d).data ?? null;

/**
 * Which way a transliteration went. With a `confidence`, the Fidel was generated from the source Latin (and is the
 * uncertain part). With a `distance`, the Latin was generated from the source Fidel and disagreed with the source Latin.
 */
export function translitDirection(d: TranslitDetails): "fidel-from-latin" | "latin-from-fidel" {
  return d.distance !== undefined && d.confidence === undefined ? "latin-from-fidel" : "fidel-from-latin";
}

/** Free-form details (audio problems) as label/value rows, in the order given. Nested values are shown as JSON. */
export function detailRows(d: unknown): { label: string; value: string }[] {
  if (d === null || typeof d !== "object" || Array.isArray(d)) return [];
  return Object.entries(d).map(([label, value]) => ({
    label,
    value: typeof value === "string" ? value : typeof value === "number" || typeof value === "boolean" ? String(value) : JSON.stringify(value),
  }));
}

// ---------------------------------------------------------------- moving through the queue

/** The item to show after `closedId` is closed: the one after it in the list, else the one before it, else none. */
export function itemAfterClosing(ids: readonly number[], closedId: number): number | undefined {
  const i = ids.indexOf(closedId);
  if (i < 0) return ids[0];
  return ids[i + 1] ?? ids[i - 1];
}

// ---------------------------------------------------------------- edits

const text = (s: string) => (s.trim() === "" ? null : s.trim());

/** The names that changed: only those are sent, since every field sent is pinned against re-scrapes. */
export function namePatch(
  edited: { am: string; latin: string },
  current: { am: string | null; latin: string | null },
): { am?: string; latin?: string | null } {
  const patch: { am?: string; latin?: string | null } = {};
  const am = text(edited.am);
  if (am !== null && am !== current.am) patch.am = am;
  const latin = text(edited.latin);
  if (latin !== current.latin) patch.latin = latin;
  return patch;
}

/** The era edit: a changed year and/or a picked era. Nothing is sent for a field that did not change. */
export function eraPatch(
  edited: { year: number | ""; generationId: string | null },
  current: { year: number | null; generationId: number | null },
): { releaseYear?: number | null; generationId?: number } {
  const patch: { releaseYear?: number | null; generationId?: number } = {};
  const year = edited.year === "" ? null : edited.year;
  if (year !== current.year) patch.releaseYear = year;
  if (edited.generationId !== null && Number(edited.generationId) !== current.generationId) {
    patch.generationId = Number(edited.generationId);
  }
  return patch;
}
