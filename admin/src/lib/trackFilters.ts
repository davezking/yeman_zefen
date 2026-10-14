import { TRACK_STATUSES, type TrackFilters } from "../api/catalog";

/** The list's filters live in the URL, so the editor can walk the same filtered list with j and k. */
export function filtersFromParams(sp: URLSearchParams): TrackFilters {
  const status = sp.get("status");
  // Ids are positive integers written in plain digits; anything else (0, -1, 0x10, 1.5) is ignored, as the API would refuse it.
  const num = (k: string) => {
    const v = sp.get(k) ?? "";
    return /^[1-9]\d{0,9}$/.test(v) ? Number(v) : undefined;
  };
  return {
    status: TRACK_STATUSES.find((s) => s === status),
    generationId: num("era"),
    genreId: num("genre"),
    q: sp.get("q")?.trim() || undefined,
  };
}

export function paramsFromFilters(f: TrackFilters): URLSearchParams {
  const sp = new URLSearchParams();
  if (f.status) sp.set("status", f.status);
  if (f.generationId) sp.set("era", String(f.generationId));
  if (f.genreId) sp.set("genre", String(f.genreId));
  if (f.q) sp.set("q", f.q);
  return sp;
}
