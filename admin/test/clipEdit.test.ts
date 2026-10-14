import { describe, expect, it } from "vitest";
import { changedStarts, clampStart, maxStartMs, nudgeStart } from "../src/lib/clipEdit";

describe("clip start editing", () => {
  it("keeps the whole window inside the track", () => {
    expect(maxStartMs(200_000, 10_000)).toBe(190_000);
    expect(maxStartMs(5_000, 10_000)).toBe(0);
    expect(clampStart(-5, 200_000, 10_000)).toBe(0);
    expect(clampStart(195_000, 200_000, 10_000)).toBe(190_000);
    expect(clampStart(1234.6, 200_000, 10_000)).toBe(1235);
  });

  it("nudges by 100 ms and 1 s and stops at the ends", () => {
    expect(nudgeStart(40_000, 100, 200_000, 10_000)).toBe(40_100);
    expect(nudgeStart(40_000, -1000, 200_000, 10_000)).toBe(39_000);
    expect(nudgeStart(50, -100, 200_000, 10_000)).toBe(0);
    expect(nudgeStart(189_950, 1000, 200_000, 10_000)).toBe(190_000);
  });

  it("lists only moved clips, at most one per clip", () => {
    const clips = [{ id: 1, type: "intro", startMs: 0 }, { id: 2, type: "middle", startMs: 60_000 }];
    expect(changedStarts(clips, {})).toEqual([]);
    expect(changedStarts(clips, { intro: 0, middle: 61_000 })).toEqual([{ clipId: 2, type: "middle", startMs: 61_000 }]);
    expect(changedStarts(clips, { intro: 500, middle: 61_000 })).toHaveLength(2);
  });
});
