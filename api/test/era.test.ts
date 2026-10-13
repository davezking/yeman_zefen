import { describe, expect, it } from "vitest";
import { assignGeneration, type EraRange } from "../src/lib/era";

const ERAS: EraRange[] = [
  { id: 1, yearFrom: null, yearTo: 1979 },
  { id: 2, yearFrom: 1980, yearTo: 1989 },
  { id: 3, yearFrom: 1990, yearTo: 1999 },
  { id: 4, yearFrom: 2000, yearTo: 2009 },
  { id: 5, yearFrom: 2010, yearTo: null },
];

describe("assignGeneration", () => {
  it.each([
    [1900, 1], [1979, 1], [1980, 2], [1989, 2], [1990, 3], [1999, 3],
    [2000, 4], [2009, 4], [2010, 5], [2030, 5],
  ])("year %i -> generation %i", (year, id) => {
    expect(assignGeneration(year, ERAS)?.id).toBe(id);
  });

  it("returns null for a missing year", () => {
    expect(assignGeneration(null, ERAS)).toBeNull();
  });

  it("returns null when no range matches", () => {
    expect(assignGeneration(1700, [{ id: 2, yearFrom: 1980, yearTo: 1989 }])).toBeNull();
  });

  it("returns the generation object, not just the id", () => {
    expect(assignGeneration(2015, ERAS)).toEqual({ id: 5, yearFrom: 2010, yearTo: null });
  });
});
