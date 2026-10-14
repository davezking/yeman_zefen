// Schemas and hooks for the pack builder API.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

const versionSchema = z.object({
  version: z.number(),
  manifestUrl: z.string(),
  trackCount: z.number(),
  totalBytes: z.number(),
  publishedAt: z.number(),
  publishedBy: z.string().nullable(),
});

const packSchema = z.object({
  id: z.number(),
  slug: z.string(),
  nameAm: z.string(),
  nameEn: z.string(),
  generationId: z.number().nullable(),
  genreId: z.number().nullable(),
  currentVersion: z.number().nullable(),
  eligibleCount: z.number(),
  versions: z.array(versionSchema),
});
export type Pack = z.infer<typeof packSchema>;

const briefTrack = z.object({ id: z.number(), titleAm: z.string().nullable(), titleLatin: z.string().nullable() });
const diffSchema = z.object({
  currentVersion: z.number().nullable(),
  eligibleCount: z.number(),
  added: z.array(briefTrack),
  removed: z.array(briefTrack),
});
export type PackDiff = z.infer<typeof diffSchema>;

export const usePacks = () =>
  useQuery({ queryKey: ["packs"], queryFn: async () => (await apiFetch("/admin/packs", z.object({ items: z.array(packSchema) }))).items });

/** What publishing now would add and remove. Always fetched fresh: it is the basis of the confirm step. */
export const usePackDiff = (id: number | null) =>
  useQuery({
    queryKey: ["pack-diff", id],
    enabled: id !== null,
    staleTime: 0,
    gcTime: 0,
    queryFn: () => apiFetch(`/admin/packs/${id}/diff`, diffSchema),
  });

export interface NewPack {
  slug: string;
  nameAm: string;
  nameEn: string;
  generationId?: number | null;
  genreId?: number | null;
}

export function useCreatePack() {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: (body: NewPack) => apiFetch("/admin/packs", z.object({ pack: packSchema }), { method: "POST", json: body }),
    onSuccess: () => void qc.invalidateQueries({ queryKey: ["packs"] }),
  });
}

export function usePublishPack() {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: (id: number) => apiFetch(`/admin/packs/${id}/versions`, z.object({ published: z.object({ version: z.number() }) }), { method: "POST" }),
    onSettled: () => void qc.invalidateQueries({ queryKey: ["packs"] }),
  });
}
