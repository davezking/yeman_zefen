import { describe, expect, it } from "vitest";
import {
  detailRows,
  eraPatch,
  isReason,
  itemAfterClosing,
  namePatch,
  parseDuplicate,
  parseTranslit,
  REASONS,
  translitDirection,
} from "../src/lib/review";

describe("parsing details", () => {
  it("reads a transliteration flag, and which way it went", () => {
    const fromLatin = parseTranslit({ field: "title", source: "Zefen", generated: "ዘፈን", confidence: 0.4 });
    expect(fromLatin).toMatchObject({ field: "title", source: "Zefen", generated: "ዘፈን" });
    expect(translitDirection(fromLatin!)).toBe("fidel-from-latin");

    const fromFidel = parseTranslit({ field: "artist", source: "Tilahun G", generated: "Tilahun Gessesse", distance: 0.5 });
    expect(translitDirection(fromFidel!)).toBe("latin-from-fidel");
  });

  it("treats details of the wrong shape as none", () => {
    expect(parseTranslit(null)).toBeNull();
    expect(parseTranslit({ field: "album", source: "x", generated: "y" })).toBeNull();
    expect(parseTranslit("text")).toBeNull();
    expect(parseDuplicate({ field: "track" })).toBeNull(); // no candidates
    expect(parseDuplicate([])).toBeNull();
  });

  it("reads duplicate candidates, with catalog ids or only source URLs", () => {
    const d = parseDuplicate({
      field: "track",
      candidates: [{ id: 7, score: 0.93, durationDiff: 0.2 }, { sourceUrl: "https://z.test/x", score: 0.88 }],
      variant_of: "live",
    });
    expect(d?.candidates).toEqual([{ id: 7, score: 0.93, durationDiff: 0.2 }, { sourceUrl: "https://z.test/x", score: 0.88 }]);
    expect(d?.variant_of).toBe("live");
  });

  it("lists free-form details as rows", () => {
    expect(detailRows({ cause: "not_in_storage", key: "source/1.mp3", durationMs: 1500, nested: { a: 1 } })).toEqual([
      { label: "cause", value: "not_in_storage" },
      { label: "key", value: "source/1.mp3" },
      { label: "durationMs", value: "1500" },
      { label: "nested", value: '{"a":1}' },
    ]);
    expect(detailRows(null)).toEqual([]);
    expect(detailRows([1, 2])).toEqual([]);
    expect(detailRows("oops")).toEqual([]);
  });

  it("knows the reasons", () => {
    expect(REASONS).toHaveLength(5);
    expect(isReason("era_unknown")).toBe(true);
    expect(isReason("nope")).toBe(false);
    expect(isReason(null)).toBe(false);
  });
});

describe("itemAfterClosing", () => {
  it("moves to the next item, else the previous one, else none", () => {
    expect(itemAfterClosing([4, 7, 9], 4)).toBe(7);
    expect(itemAfterClosing([4, 7, 9], 7)).toBe(9);
    expect(itemAfterClosing([4, 7, 9], 9)).toBe(7);
    expect(itemAfterClosing([4], 4)).toBeUndefined();
    expect(itemAfterClosing([], 4)).toBeUndefined();
  });

  it("falls back to the first item when the closed one is not in the list", () => {
    expect(itemAfterClosing([4, 7], 99)).toBe(4);
  });
});

describe("namePatch", () => {
  const current = { am: "ዘፈን", latin: "Zefen" };
  it("sends nothing when nothing changed", () => {
    expect(namePatch({ am: "ዘፈን", latin: "Zefen" }, current)).toEqual({});
    expect(namePatch({ am: "  ዘፈን ", latin: " Zefen " }, current)).toEqual({});
  });
  it("sends only the changed name", () => {
    expect(namePatch({ am: "ዘፈኑ", latin: "Zefen" }, current)).toEqual({ am: "ዘፈኑ" });
    expect(namePatch({ am: "ዘፈን", latin: "Zefen 2" }, current)).toEqual({ latin: "Zefen 2" });
  });
  it("clears the Latin name when it is emptied, but never the Fidel one", () => {
    expect(namePatch({ am: "ዘፈን", latin: "  " }, current)).toEqual({ latin: null });
    expect(namePatch({ am: "", latin: "Zefen" }, current)).toEqual({});
  });
  it("fills a Latin name that was missing", () => {
    expect(namePatch({ am: "ዘፈን", latin: "Zefen" }, { am: "ዘፈን", latin: null })).toEqual({ latin: "Zefen" });
  });
});

describe("eraPatch", () => {
  it("sends the year when it changed, and the era when one was picked", () => {
    expect(eraPatch({ year: 1975, generationId: null }, { year: null, generationId: null })).toEqual({ releaseYear: 1975 });
    expect(eraPatch({ year: "", generationId: "2" }, { year: null, generationId: null })).toEqual({ generationId: 2 });
    expect(eraPatch({ year: 1975, generationId: "2" }, { year: null, generationId: null })).toEqual({ releaseYear: 1975, generationId: 2 });
  });
  it("sends nothing for what did not change", () => {
    expect(eraPatch({ year: 1975, generationId: "2" }, { year: 1975, generationId: 2 })).toEqual({});
    expect(eraPatch({ year: "", generationId: null }, { year: null, generationId: null })).toEqual({});
  });
  it("clears the year when it is emptied", () => {
    expect(eraPatch({ year: "", generationId: null }, { year: 1975, generationId: 2 })).toEqual({ releaseYear: null });
  });
});
