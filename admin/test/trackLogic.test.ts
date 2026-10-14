import { describe, expect, it } from "vitest";
import type { TrackDetail } from "../src/api/catalog";
import { runBulk } from "../src/lib/bulk";
import { filtersFromParams, paramsFromFilters } from "../src/lib/trackFilters";
import { buildPatch, toForm } from "../src/lib/trackForm";

const detail = (over: Partial<TrackDetail["track"]> = {}, genreIds = [1, 2]): TrackDetail => ({
  track: {
    id: 7,
    artistId: 3,
    titleAm: "ሐሰት ሠላም",
    titleLatin: "Haset Selam",
    album: null,
    releaseYear: 1975,
    generationId: 2,
    generationOverridden: false,
    sourceUrl: "https://ethiozeima.com/x/",
    durationMs: 200000,
    status: "ingested",
    ...over,
  },
  artist: { id: 3, nameAm: "ጥላሁን", nameLatin: "Tilahun" },
  clips: [],
  openReviewItems: [],
  genreIds,
});

describe("buildPatch", () => {
  it("is empty for an untouched form", () => {
    const d = detail();
    expect(buildPatch(toForm(d), d)).toEqual({});
  });

  it("sends only the fields that changed, so untouched fields are not pinned against re-scrapes", () => {
    const d = detail();
    const form = { ...toForm(d), titleLatin: "Haset Selam 2", releaseYear: 1976 as number | "" };
    expect(buildPatch(form, d)).toEqual({ titleLatin: "Haset Selam 2", releaseYear: 1976 });
  });

  it("sends a Fidel title exactly as typed, homophones and all", () => {
    const d = detail();
    const typed = "ሐሰት ሠላም ኅብረት";
    expect(buildPatch({ ...toForm(d), titleAm: typed }, d)).toEqual({ titleAm: typed });
  });

  it("turns a cleared text field into null, and ignores surrounding spaces", () => {
    const d = detail({ album: "Old" });
    expect(buildPatch({ ...toForm(d), album: "   " }, d)).toEqual({ album: null });
    expect(buildPatch({ ...toForm(d), titleLatin: "  Haset Selam  " }, d)).toEqual({});
  });

  it("clearing the year or the era sends null", () => {
    const d = detail();
    expect(buildPatch({ ...toForm(d), releaseYear: "", generationId: null }, d)).toEqual({
      releaseYear: null,
      generationId: null,
    });
  });

  it("picking the auto-assigned era pins it; picking it again on a pinned track sends nothing", () => {
    const auto = detail({ generationId: 2, generationOverridden: false });
    expect(buildPatch({ ...toForm(auto), eraPicked: true }, auto)).toEqual({ generationId: 2 });
    const pinned = detail({ generationId: 2, generationOverridden: true });
    expect(buildPatch({ ...toForm(pinned), eraPicked: true }, pinned)).toEqual({});
    // Clearing is never a pin, whatever the flag says.
    expect(buildPatch({ ...toForm(auto), generationId: null, eraPicked: false }, auto)).toEqual({ generationId: null });
  });

  it("compares genres as a set, ignoring order", () => {
    const d = detail({}, [1, 2]);
    expect(buildPatch({ ...toForm(d), genreIds: ["2", "1"] }, d)).toEqual({});
    expect(buildPatch({ ...toForm(d), genreIds: ["2", "5"] }, d)).toEqual({ genreIds: [2, 5] });
    expect(buildPatch({ ...toForm(d), genreIds: [] }, d)).toEqual({ genreIds: [] });
  });

  it("sends artistId when another artist was picked", () => {
    const d = detail();
    expect(buildPatch({ ...toForm(d), artist: { id: 9, nameAm: "ሌላ", nameLatin: null } }, d)).toEqual({ artistId: 9 });
  });
});

describe("track list filters in the URL", () => {
  it("round-trips every filter", () => {
    const filters = { status: "needs_review" as const, generationId: 2, genreId: 4, q: "ዘፈን 1" };
    expect(filtersFromParams(paramsFromFilters(filters))).toEqual(filters);
  });

  it("drops values it does not understand", () => {
    const sp = new URLSearchParams("status=bogus&era=abc&genre=1.5&q=%20%20");
    expect(filtersFromParams(sp)).toEqual({ status: undefined, generationId: undefined, genreId: undefined, q: undefined });
  });

  it("accepts only positive ids, as the API does", () => {
    for (const bad of ["0", "-1", "0x10", "1e3", "01", " 2", "99999999999"]) {
      expect(filtersFromParams(new URLSearchParams({ era: bad })).generationId, bad).toBeUndefined();
    }
    expect(filtersFromParams(new URLSearchParams({ era: "3", genre: "12" }))).toMatchObject({ generationId: 3, genreId: 12 });
  });

  it("writes only the filters that are set", () => {
    expect(paramsFromFilters({}).toString()).toBe("");
    expect(paramsFromFilters({ status: "approved" }).toString()).toBe("status=approved");
  });
});

describe("runBulk", () => {
  it("reports every row, in order, and never throws", async () => {
    const results = await runBulk(
      [1, 2, 3, 4, 5],
      async (n) => {
        if (n % 2 === 0) throw new Error(`no ${n}`);
      },
      (e) => (e as Error).message,
    );
    expect(results.map((r) => [r.item, r.ok])).toEqual([[1, true], [2, false], [3, true], [4, false], [5, true]]);
    expect(results[1]).toMatchObject({ ok: false, message: "no 2" });
  });

  it("never runs more than `concurrency` at once", async () => {
    let running = 0;
    let peak = 0;
    await runBulk(
      Array.from({ length: 12 }, (_, i) => i),
      async () => {
        running++;
        peak = Math.max(peak, running);
        await new Promise((r) => setTimeout(r, 5));
        running--;
      },
      String,
      3,
    );
    expect(peak).toBe(3);
  });

  it("handles an empty list", async () => {
    expect(await runBulk([], async () => undefined, String)).toEqual([]);
  });
});

describe("mmss", () => {
  it("formats minutes, seconds and tenths, rounding the whole value once", async () => {
    const { mmss } = await import("../src/lib/format");
    expect(mmss(0)).toBe("0:00.0");
    expect(mmss(12_340)).toBe("0:12.3");
    expect(mmss(90_000)).toBe("1:30.0");
    expect(mmss(59_960)).toBe("1:00.0");
    expect(mmss(119_970)).toBe("2:00.0");
    expect(mmss(605_049)).toBe("10:05.0");
  });
});
