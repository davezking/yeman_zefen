# Pack manifest (schema 1)

The contract between the pack builder (`api/src/lib/packs.ts`) and the app. The zod schema that enforces it is
`api/src/lib/packManifest.ts`; tests validate every published manifest against it.

## Where it lives

- `packs/{slug}/v{n}/manifest.json` in the public bucket `yz-clips`, served at `CDN_BASE_URL`.
- Written once with `Cache-Control: public, max-age=31536000, immutable`. A version's manifest is never replaced:
  the write is create-only, and a publish that finds a manifest already at the next number uses the one after it.
- The app finds the current one through `GET /v1/packs` (`manifestUrl`).

## Format

```json
{
  "schema": 1,
  "slug": "golden-era",
  "version": 3,
  "publishedAt": 1760000000000,
  "names": { "am": "...", "en": "Golden era" },
  "generationId": 2,
  "genreId": null,
  "tracks": [
    {
      "id": 41,
      "titleAm": "...", "titleLatin": "...",
      "artistId": 7, "artistAm": "...", "artistLatin": "...",
      "generationId": 2,
      "genreIds": [1, 4],
      "releaseYear": 1975,
      "clips": {
        "intro":  { "url": "https://cdn.example.com/clips/41/intro-v2.mp3",  "sha256": "<64 hex>", "bytes": 160412, "lengthMs": 10000 },
        "middle": { "url": "https://cdn.example.com/clips/41/middle-v1.mp3", "sha256": "<64 hex>", "bytes": 158900, "lengthMs": 10000 }
      }
    }
  ],
  "totalBytes": 319312
}
```

| Field | Notes |
|---|---|
| `schema` | Always `1`. A breaking change bumps it; apps refuse a schema they do not know. |
| `version` | Integer, counts up per pack from 1. May skip numbers. |
| `publishedAt` | Epoch milliseconds, UTC. |
| `generationId`, `genreId` | The pack's filter, `null` when it has none. Informational: `tracks` is the list. |
| `tracks` | At least one. Ordered by track id. Each track once. |
| `titleAm`, `titleLatin`, `artistLatin`, `releaseYear` | May be `null`. |
| `genreIds` | Ascending; empty when the track has no genre. |
| `clips.*.url` | Absolute. Clip files are versioned by name, so a url's content does not change. |
| `clips.*.sha256` | Lowercase hex. The app verifies each download against it. |
| `totalBytes` | Sum of every clip's `bytes`. |

Unknown fields are rejected by the writer's schema; readers should ignore ones they do not know.

## Who may be in a pack

Only tracks that are `approved` with both clips `ready` (file, checksum and size recorded), and that match the
pack's era and genre filter. Retiring a track later does not touch published versions; the next version leaves it out.

## `GET /v1/packs`

Public, cached for 5 minutes. Only packs with a published version:

```json
{ "packs": [ { "slug": "golden-era", "names": { "am": "...", "en": "..." }, "generationId": 2, "genreId": null,
               "version": 3, "manifestUrl": "https://cdn.example.com/packs/golden-era/v3/manifest.json",
               "trackCount": 120, "totalBytes": 19000000, "publishedAt": 1760000000000 } ] }
```

## Admin API

- `POST /admin/packs { slug, nameAm, nameEn, generationId?, genreId? }`
- `GET /admin/packs`: packs with `eligibleCount` and version history.
- `GET /admin/packs/:id/diff`: tracks a new version would add and remove against the current one.
- `POST /admin/packs/:id/versions { trackIds? }`: publish. 409 `tracks_not_eligible` / `no_eligible_tracks`.

A publish costs a constant number of D1 statements however large the pack (see `test/packs.test.ts`).
