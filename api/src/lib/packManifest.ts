// The pack manifest: the contract the app downloads. Documented in docs/pack-manifest.md; this schema is what
// the Worker checks a manifest against before it is published, and what the tests hold the writer to.
import { z } from "zod";

export const MANIFEST_SCHEMA_VERSION = 1;

const clip = z.strictObject({
  url: z.url(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  bytes: z.number().int().positive(),
  lengthMs: z.number().int().positive(),
});

export const manifestTrack = z.strictObject({
  id: z.number().int().positive(),
  titleAm: z.string().nullable(),
  titleLatin: z.string().nullable(),
  artistId: z.number().int().positive(),
  artistAm: z.string(),
  artistLatin: z.string().nullable(),
  generationId: z.number().int().positive().nullable(),
  genreIds: z.array(z.number().int().positive()),
  releaseYear: z.number().int().nullable(),
  clips: z.strictObject({ intro: clip, middle: clip }),
});

export const packManifest = z
  .strictObject({
    schema: z.literal(MANIFEST_SCHEMA_VERSION),
    slug: z.string().min(1),
    version: z.number().int().positive(),
    publishedAt: z.number().int().positive(),
    names: z.strictObject({ am: z.string(), en: z.string() }),
    generationId: z.number().int().positive().nullable(),
    genreId: z.number().int().positive().nullable(),
    tracks: z.array(manifestTrack).min(1),
    totalBytes: z.number().int().positive(),
  })
  .refine((m) => m.totalBytes === m.tracks.reduce((n, t) => n + t.clips.intro.bytes + t.clips.middle.bytes, 0), {
    message: "totalBytes must equal the sum of every clip's bytes",
    path: ["totalBytes"],
  })
  .refine((m) => new Set(m.tracks.map((t) => t.id)).size === m.tracks.length, {
    message: "a track appears once",
    path: ["tracks"],
  });
export type PackManifest = z.infer<typeof packManifest>;

export const manifestKey = (slug: string, version: number) => `packs/${slug}/v${version}/manifest.json`;
