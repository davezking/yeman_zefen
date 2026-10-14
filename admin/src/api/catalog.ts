// Schemas and hooks for the catalog admin API (tracks, artists, eras, genres, review items).
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { REASONS } from "../lib/review";
import { apiFetch } from "./client";

export const TRACK_STATUSES = ["ingested", "needs_review", "approved", "rejected", "retired"] as const;
export type TrackStatus = (typeof TRACK_STATUSES)[number];

const clipStatusSchema = z.enum(["pending", "ready", "failed"]);
export type ClipStatus = z.infer<typeof clipStatusSchema>;

export const trackRowSchema = z.object({
  id: z.number(),
  titleAm: z.string().nullable(),
  titleLatin: z.string().nullable(),
  releaseYear: z.number().nullable(),
  generationId: z.number().nullable(),
  generationOverridden: z.boolean(),
  status: z.enum(TRACK_STATUSES),
  artistId: z.number(),
  artistNameAm: z.string(),
  artistNameLatin: z.string().nullable(),
  // null: the clip row does not exist yet.
  introStatus: clipStatusSchema.nullable(),
  middleStatus: clipStatusSchema.nullable(),
  openFlagCount: z.number(),
});
export type TrackRow = z.infer<typeof trackRowSchema>;

const trackListSchema = z.object({ items: z.array(trackRowSchema), nextCursor: z.string().nullable() });

export const REVIEW_STATUSES = ["open", "resolved", "dismissed"] as const;

const reviewItemSchema = z.object({
  id: z.number(),
  reason: z.enum(REASONS),
  detailsJson: z.string().nullable(),
  status: z.enum(REVIEW_STATUSES),
});
export type ReviewItem = z.infer<typeof reviewItemSchema>;

const clipSchema = z.object({
  id: z.number(),
  type: z.enum(["intro", "middle"]),
  startMs: z.number(),
  lengthMs: z.number(),
  status: clipStatusSchema,
  url: z.string().nullable(),
});
export type Clip = z.infer<typeof clipSchema>;

export const artistSchema = z.object({ id: z.number(), nameAm: z.string(), nameLatin: z.string().nullable() });
export type Artist = z.infer<typeof artistSchema>;

export const trackDetailSchema = z.object({
  track: z.object({
    id: z.number(),
    artistId: z.number(),
    titleAm: z.string().nullable(),
    titleLatin: z.string().nullable(),
    album: z.string().nullable(),
    releaseYear: z.number().nullable(),
    generationId: z.number().nullable(),
    generationOverridden: z.boolean(),
    sourceUrl: z.string().nullable(),
    durationMs: z.number().nullable(),
    status: z.enum(TRACK_STATUSES),
  }),
  artist: artistSchema.nullable(),
  clips: z.array(clipSchema),
  openReviewItems: z.array(reviewItemSchema),
  genreIds: z.array(z.number()),
});
export type TrackDetail = z.infer<typeof trackDetailSchema>;

const generationSchema = z.object({
  id: z.number(),
  nameAm: z.string(),
  nameEn: z.string(),
  yearFrom: z.number().nullable(),
  yearTo: z.number().nullable(),
});
export type Generation = z.infer<typeof generationSchema>;

const genreSchema = z.object({ id: z.number(), nameAm: z.string(), nameEn: z.string() });
export type Genre = z.infer<typeof genreSchema>;

// ----------------------------------------------------------------- list filters

export interface TrackFilters {
  status?: TrackStatus;
  generationId?: number;
  genreId?: number;
  q?: string;
}

function toQuery(params: Record<string, string | number | undefined>): string {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") sp.set(k, String(v));
  const s = sp.toString();
  return s ? `?${s}` : "";
}

export const keys = {
  tracks: (f: TrackFilters) => ["tracks", f] as const,
  track: (id: number) => ["track", id] as const,
};

const trackDetailFetcher = (id: number) => () => apiFetch(`/admin/tracks/${id}`, trackDetailSchema);

export function useTrackList(filters: TrackFilters) {
  return useInfiniteQuery({
    queryKey: keys.tracks(filters),
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) => apiFetch(`/admin/tracks${toQuery({ ...filters, cursor: pageParam })}`, trackListSchema),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
}

/**
 * The track that follows `id` in the filtered list, asked of the API (the list is newest first and its cursor is
 * "ids below this one"). Works when that track is not loaded yet, and when approving just removed `id` from the list.
 */
export async function fetchTrackAfter(filters: TrackFilters, id: number): Promise<number | undefined> {
  const page = await apiFetch(`/admin/tracks${toQuery({ ...filters, cursor: String(id) })}`, trackListSchema);
  return page.items[0]?.id;
}

export const useTrack = (id: number) => useQuery({ queryKey: keys.track(id), queryFn: trackDetailFetcher(id) });

/** Resolves once the track's detail is cached, so moving to it never shows a loading state. */
export function useEnsureTrack() {
  const qc = useQueryClient();
  return (id: number) => qc.ensureQueryData({ queryKey: keys.track(id), queryFn: trackDetailFetcher(id) });
}

/** The track's detail as the server has it now, not as cached: for deciding what to offer after an edit. */
export function useFreshTrack() {
  const qc = useQueryClient();
  return (id: number) => qc.fetchQuery({ queryKey: keys.track(id), queryFn: trackDetailFetcher(id), staleTime: 0 });
}

export function usePrefetchTrack() {
  const qc = useQueryClient();
  return (id: number) => void qc.prefetchQuery({ queryKey: keys.track(id), queryFn: trackDetailFetcher(id) });
}

// ----------------------------------------------------------------- lookups

export const useGenerations = () =>
  useQuery({
    queryKey: ["generations"],
    queryFn: async () => (await apiFetch("/admin/generations", z.object({ items: z.array(generationSchema) }))).items,
    staleTime: Infinity,
  });

export const useGenres = () =>
  useQuery({
    queryKey: ["genres"],
    queryFn: async () => (await apiFetch("/admin/genres", z.object({ items: z.array(genreSchema) }))).items,
    staleTime: Infinity,
  });

export function useArtistSearch(q: string) {
  return useQuery({
    queryKey: ["artists", q],
    queryFn: async () =>
      (await apiFetch(`/admin/artists${toQuery({ q })}`, z.object({ items: z.array(artistSchema) }))).items,
    placeholderData: (prev) => prev,
  });
}

// ----------------------------------------------------------------- mutations

/** The fields the editor can change. Send only what changed: every edited field is pinned against re-scrapes. */
export interface TrackPatch {
  titleAm?: string | null;
  titleLatin?: string | null;
  album?: string | null;
  releaseYear?: number | null;
  generationId?: number | null;
  artistId?: number;
  genreIds?: number[];
}

/** `silent`: the caller shows errors itself, so the global notification is switched off. */
export function usePatchTrack(id: number, { silent = false }: { silent?: boolean } = {}) {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent },
    mutationFn: (patch: TrackPatch) =>
      apiFetch(`/admin/tracks/${id}`, trackDetailSchema, { method: "PATCH", json: patch }),
    onSuccess: (detail) => {
      qc.setQueryData(keys.track(id), detail);
      void qc.invalidateQueries({ queryKey: ["tracks"] });
    },
  });
}

export type TrackAction = "approve" | "reject";

/**
 * Approve or reject one track. Rejections of the API (409: clips not ready, wrong status) are shown by the caller,
 * next to the button or in the bulk result, so the global notification is switched off for these.
 */
export function useTrackAction({ invalidateList = true }: { invalidateList?: boolean } = {}) {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: ({ id, action }: { id: number; action: TrackAction }) =>
      apiFetch(`/admin/tracks/${id}/${action}`, trackDetailSchema, { method: "POST" }),
    onSuccess: (detail, { id }) => {
      qc.setQueryData(keys.track(id), detail);
    },
    // A bulk run turns this off and refreshes the list once at the end, not once per row.
    onSettled: () => {
      if (invalidateList) void qc.invalidateQueries({ queryKey: ["tracks"] });
    },
  });
}

export function useCreateArtist() {
  return useMutation({
    meta: { silent: true },
    mutationFn: (body: { nameAm: string; nameLatin?: string }) =>
      apiFetch("/admin/artists", z.object({ artist: artistSchema }), { method: "POST", json: body }).then((r) => r.artist),
  });
}

export function useCloseReviewItem(trackId: number) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: number; action: "resolve" | "dismiss" }) =>
      apiFetch(`/admin/review-items/${id}/${action}`, z.object({ item: reviewItemSchema }), { method: "POST" }),
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: keys.track(trackId) });
      void qc.invalidateQueries({ queryKey: ["tracks"] });
    },
  });
}

// ----------------------------------------------------------------- clip editor

const jobSchema = z.object({
  id: z.number(),
  kind: z.string(),
  status: z.enum(["queued", "running", "succeeded", "failed"]),
  ghRunUrl: z.string().nullable(),
  summary: z.unknown(),
});
export type Job = z.infer<typeof jobSchema>;

/** A signed URL for the track's private source audio. Short-lived: ask again for each editing session. */
export function useSourceUrl(trackId: number) {
  return useQuery({
    queryKey: ["source-url", trackId],
    queryFn: () => apiFetch(`/admin/tracks/${trackId}/source-url`, z.object({ url: z.string(), expiresAt: z.number() })),
    staleTime: 5 * 60_000,
    gcTime: 5 * 60_000,
    retry: false,
  });
}

/** Move a clip's start. The clip becomes pending and `job` is its recut (null when the job could not be started). */
export function usePatchClip() {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: ({ clipId, startMs }: { clipId: number; startMs: number }) =>
      apiFetch(
        `/admin/clips/${clipId}`,
        z.object({ job: jobSchema.nullable(), clip: z.object({ id: z.number(), trackId: z.number() }) }),
        { method: "PATCH", json: { start_ms: startMs } },
      ),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["tracks"] });
    },
  });
}

const POLL_MS = 5_000;

/** A job, refreshed every 5 s until it has succeeded or failed. */
export function useJobPoll(jobId: number | null) {
  return useQuery({
    queryKey: ["job", jobId],
    enabled: jobId !== null,
    queryFn: async () => (await apiFetch(`/admin/jobs?id=${jobId}`, z.object({ jobs: z.array(jobSchema) }))).jobs[0]!,
    refetchInterval: (q) => (q.state.data && (q.state.data.status === "succeeded" || q.state.data.status === "failed") ? false : POLL_MS),
  });
}
