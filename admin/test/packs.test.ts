import { diffSchema, packSchema } from "../src/api/packs";
import { describe, expect, it } from "vitest";
import { megabytes, SLUG_RE } from "../src/lib/packs";

describe("pack form helpers", () => {
  it("accepts the slugs the API accepts", () => {
    for (const ok of ["a", "golden-era", "pack-2"]) expect(SLUG_RE.test(ok)).toBe(true);
    for (const bad of ["", "Golden", "a b", "-a", "a--b", "a-"]) expect(SLUG_RE.test(bad)).toBe(false);
  });
  it("shows sizes in MB", () => expect(megabytes(5_242_880)).toBe("5.0 MB"));
});

// The admin schemas must accept what the API really sends (shapes from api/src/routes/admin/packs.ts).

describe("pack API schemas", () => {
  it("parse a GET /admin/packs row", () => {
    const row = {
      id: 1, slug: "all", nameAm: "ሁሉም", nameEn: "All", generationId: null, genreId: null, currentVersion: 1, eligibleCount: 3,
      versions: [{ version: 1, manifestUrl: "https://cdn/x", trackCount: 3, totalBytes: 10, publishedAt: 1, publishedBy: null }],
    };
    expect(packSchema.safeParse(row).success).toBe(true);
  });
  it("parse a diff", () => {
    const diff = { currentVersion: null, nextVersion: 1, eligibleCount: 1, trackIds: [5], added: [{ id: 5, titleAm: null, titleLatin: "x" }], removed: [] };
    expect(diffSchema.safeParse(diff).success).toBe(true);
  });
});
