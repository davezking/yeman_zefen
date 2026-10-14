/** Where a clip may start so that all `lengthMs` of it still lie inside a track of `durationMs`. */
export const maxStartMs = (durationMs: number, lengthMs: number) => Math.max(0, durationMs - lengthMs);

/** `startMs` moved by `deltaMs` (whole ms), kept inside the track. */
export function nudgeStart(startMs: number, deltaMs: number, durationMs: number, lengthMs: number): number {
  return clampStart(startMs + deltaMs, durationMs, lengthMs);
}

export function clampStart(startMs: number, durationMs: number, lengthMs: number): number {
  return Math.min(maxStartMs(durationMs, lengthMs), Math.max(0, Math.round(startMs)));
}

export const PREVIEW_SECONDS = [3, 5, 10] as const;

/** The clips whose start was moved, as the PATCH calls to make: at most one per clip, so at most two jobs. */
export function changedStarts(
  clips: { id: number; type: string; startMs: number }[],
  edited: Record<string, number>,
): { clipId: number; type: string; startMs: number }[] {
  return clips.flatMap((c) => (edited[c.type] !== undefined && edited[c.type] !== c.startMs ? [{ clipId: c.id, type: c.type, startMs: edited[c.type]! }] : []));
}
