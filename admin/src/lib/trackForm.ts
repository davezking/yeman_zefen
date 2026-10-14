// The track editor's form values, and how they turn into an API patch.
import type { Artist, TrackDetail, TrackPatch } from "../api/catalog";

export interface FormValues {
  titleAm: string;
  titleLatin: string;
  album: string;
  releaseYear: number | "";
  generationId: string | null;
  /** The admin picked the era in this form, so it is pinned even if it is the era already assigned. */
  eraPicked: boolean;
  genreIds: string[];
  artist: Artist;
}

export const toForm = (d: TrackDetail): FormValues => ({
  titleAm: d.track.titleAm ?? "",
  titleLatin: d.track.titleLatin ?? "",
  album: d.track.album ?? "",
  releaseYear: d.track.releaseYear ?? "",
  generationId: d.track.generationId === null ? null : String(d.track.generationId),
  eraPicked: false,
  genreIds: d.genreIds.map(String),
  // A track always has an artist; the detail response types it as nullable only because of the join.
  artist: d.artist ?? { id: d.track.artistId, nameAm: `Artist ${d.track.artistId}`, nameLatin: null },
});

const text = (s: string) => (s.trim() === "" ? null : s.trim());
const sameSet = (a: number[], b: number[]) => a.length === b.length && [...a].sort().join() === [...b].sort().join();

/**
 * Only the fields that changed. The API pins every field it is sent against re-scrapes, so sending an
 * untouched field would quietly stop the scraper from improving it.
 */
export function buildPatch(v: FormValues, d: TrackDetail): TrackPatch {
  const patch: TrackPatch = {};
  if (text(v.titleAm) !== d.track.titleAm) patch.titleAm = text(v.titleAm);
  if (text(v.titleLatin) !== d.track.titleLatin) patch.titleLatin = text(v.titleLatin);
  if (text(v.album) !== d.track.album) patch.album = text(v.album);
  const year = v.releaseYear === "" ? null : v.releaseYear;
  if (year !== d.track.releaseYear) patch.releaseYear = year;
  const era = v.generationId === null ? null : Number(v.generationId);
  // Picking the era that was auto-assigned still pins it, so a later year edit or re-scrape cannot move it.
  if (era !== d.track.generationId || (v.eraPicked && era !== null && !d.track.generationOverridden)) {
    patch.generationId = era;
  }
  if (v.artist.id !== d.track.artistId) patch.artistId = v.artist.id;
  const genreIds = v.genreIds.map(Number);
  if (!sameSet(genreIds, d.genreIds)) patch.genreIds = genreIds;
  return patch;
}
