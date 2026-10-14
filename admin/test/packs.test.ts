import { describe, expect, it } from "vitest";
import { megabytes, SLUG_RE } from "../src/lib/packs";

describe("pack form helpers", () => {
  it("accepts the slugs the API accepts", () => {
    for (const ok of ["a", "golden-era", "pack-2"]) expect(SLUG_RE.test(ok)).toBe(true);
    for (const bad of ["", "Golden", "a b", "-a", "a--b", "a-"]) expect(SLUG_RE.test(bad)).toBe(false);
  });
  it("shows sizes in MB", () => expect(megabytes(5_242_880)).toBe("5.0 MB"));
});
