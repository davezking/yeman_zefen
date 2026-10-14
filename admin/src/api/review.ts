// Hooks for the review queue: its items and counts, and the actions the resolution panels take.
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { REASONS, type Reason } from "../lib/review";
import { artistSchema, TRACK_STATUSES, trackDetailSchema } from "./catalog";
import { apiFetch } from "./client";

const trackSummarySchema = z.object({
  id: z.number(),
  titleAm: z.string().nullable(),
  titleLatin: z.string().nullable(),
  releaseYear: z.number().nullable(),
  generationId: z.number().nullable(),
  status: z.enum(TRACK_STATUSES),
  durationMs: z.number().nullable(),
  sourceUrl: z.string().nullable(),
  artistId: z.number(),
  artistNameAm: z.string(),
  artistNameLatin: z.string().nullable(),
});
export type TrackSummary = z.infer<typeof trackSummarySchema>;

const reviewRowSchema = z.object({
  id: z.number(),
  reason: z.enum(REASONS),
  status: z.enum(["open", "resolved", "dismissed"]),
  /** Free-form JSON from the scraper or the cutter; each panel parses the shape it expects. */
  details: z.unknown(),
  track: trackSummarySchema,
});
export type ReviewRow = z.infer<typeof reviewRowSchema>;

const reviewListSchema = z.object({ items: z.array(reviewRowSchema), nextCursor: z.string().nullable() });
const countsSchema = z.object({ counts: z.record(z.enum(REASONS), z.number()) });

export const reviewKeys = {
  all: ["review"] as const,
  counts: ["review", "counts"] as const,
  list: (reason: Reason) => ["review", "list", reason] as const,
};

export function useReviewCounts() {
  return useQuery({
    queryKey: reviewKeys.counts,
    queryFn: async () => (await apiFetch("/admin/review-items/counts", countsSchema)).counts,
  });
}

/** `enabled: false` while the tab is not known yet, so no list is fetched for a tab that will not be shown. */
export function useReviewList(reason: Reason, { enabled = true }: { enabled?: boolean } = {}) {
  return useInfiniteQuery({
    enabled,
    queryKey: reviewKeys.list(reason),
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      apiFetch(`/admin/review-items?reason=${reason}${pageParam ? `&cursor=${pageParam}` : ""}`, reviewListSchema),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
}

/** Refresh everything a change can touch. Closing an item changes the queue, the counts, the track's own items, and possibly the track list. */
export function useRefreshQueue() {
  const qc = useQueryClient();
  return () => {
    void qc.invalidateQueries({ queryKey: reviewKeys.all });
    void qc.invalidateQueries({ queryKey: ["track"] });
    void qc.invalidateQueries({ queryKey: ["tracks"] });
  };
}

const itemSchema = z.object({ item: z.object({ id: z.number() }) });

export function useCloseItem() {
  const refresh = useRefreshQueue();
  return useMutation({
    meta: { silent: true }, // the panel shows what went wrong, next to the buttons
    mutationFn: ({ id, action }: { id: number; action: "resolve" | "dismiss" }) =>
      apiFetch(`/admin/review-items/${id}/${action}`, itemSchema, { method: "POST" }),
    onSettled: refresh,
  });
}

export function useMarkDuplicate() {
  const refresh = useRefreshQueue();
  return useMutation({
    meta: { silent: true },
    mutationFn: ({ trackId, canonicalTrackId }: { trackId: number; canonicalTrackId: number }) =>
      apiFetch(`/admin/tracks/${trackId}/mark-duplicate`, trackDetailSchema, { method: "POST", json: { canonicalTrackId } }),
    onSettled: refresh,
  });
}

/** Retire an approved track, or reject one that was never approved: the status machine has no retire for those. */
export function useRetireOrReject() {
  const refresh = useRefreshQueue();
  return useMutation({
    meta: { silent: true },
    mutationFn: ({ id, action }: { id: number; action: "retire" | "reject" }) =>
      apiFetch(`/admin/tracks/${id}/${action}`, trackDetailSchema, { method: "POST" }),
    onSettled: refresh,
  });
}

// ---------------------------------------------------------------- artists

const artistDetailSchema = z.object({
  artist: artistSchema,
  aliases: z.array(z.object({ id: z.number(), alias: z.string() })),
  trackCount: z.number(),
});
export type ArtistDetail = z.infer<typeof artistDetailSchema>;

export const useArtistDetail = (id: number | undefined) =>
  useQuery({
    queryKey: ["artist", id],
    queryFn: () => apiFetch(`/admin/artists/${id}`, artistDetailSchema),
    enabled: id !== undefined,
  });

export function usePatchArtist(id: number) {
  const refresh = useRefreshQueue();
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: (patch: { nameAm?: string; nameLatin?: string | null }) =>
      apiFetch(`/admin/artists/${id}`, z.object({ artist: artistSchema }), { method: "PATCH", json: patch }),
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: ["artist"] });
      refresh();
    },
  });
}

/** Merge artist `fromId` into `intoId` (admins only). The old name and aliases become aliases of the survivor. */
export function useMergeArtist() {
  const refresh = useRefreshQueue();
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: ({ fromId, intoId }: { fromId: number; intoId: number }) =>
      apiFetch(
        `/admin/artists/${fromId}/merge`,
        z.object({ merged: z.object({ tracksMoved: z.number(), aliasesMoved: z.number() }) }),
        { method: "POST", json: { intoArtistId: intoId } },
      ),
    onSuccess: (_data, { fromId }) => {
      // The merged artist no longer exists: forget it rather than ask for it again (that would be a 404).
      qc.removeQueries({ queryKey: ["artist", fromId] });
    },
    onSettled: (_data, _error, { fromId }) => {
      void qc.invalidateQueries({ queryKey: ["artist"], predicate: (q) => q.queryKey[1] !== fromId });
      refresh();
    },
  });
}

// ---------------------------------------------------------------- jobs

/** Ask for the clips of one track to be cut again. */
export function useStartCut() {
  return useMutation({
    meta: { silent: true },
    mutationFn: (trackId: number) =>
      apiFetch("/admin/jobs", z.object({ job: z.object({ id: z.number() }) }), {
        method: "POST",
        json: { kind: "cut", params: { trackIds: [trackId] } },
      }).then((r) => r.job),
  });
}
