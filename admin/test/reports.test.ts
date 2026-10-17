import { describe, expect, it } from "vitest";
import { MAX_REPORT_DAYS, includesToday, isDay, lastMonth, lastQuarter, rangeError, reportFilename } from "../src/lib/reports";

const at = (day: string, time = "12:00:00") => Date.parse(`${day}T${time}Z`);

describe("report presets", () => {
  it("last month is the whole calendar month before this one", () => {
    expect(lastMonth(at("2026-10-17"))).toEqual({ from: "2026-09-01", to: "2026-09-30" });
    expect(lastMonth(at("2026-03-01"))).toEqual({ from: "2026-02-01", to: "2026-02-28" });
    expect(lastMonth(at("2028-03-31"))).toEqual({ from: "2028-02-01", to: "2028-02-29" });
  });

  it("last month in January is December of the year before", () => {
    expect(lastMonth(at("2026-01-15"))).toEqual({ from: "2025-12-01", to: "2025-12-31" });
  });

  it("last quarter is the whole calendar quarter before this one", () => {
    expect(lastQuarter(at("2026-10-17"))).toEqual({ from: "2026-07-01", to: "2026-09-30" });
    expect(lastQuarter(at("2026-07-01"))).toEqual({ from: "2026-04-01", to: "2026-06-30" });
    expect(lastQuarter(at("2026-06-30", "23:59:59"))).toEqual({ from: "2026-01-01", to: "2026-03-31" });
  });

  it("last quarter in the first quarter is the last quarter of the year before", () => {
    expect(lastQuarter(at("2026-02-10"))).toEqual({ from: "2025-10-01", to: "2025-12-31" });
  });

  it("uses UTC days, not the local day", () => {
    // 23:30 UTC on 30 Sep is already 1 Oct in Addis Ababa (UTC+3), but the roll-up counts UTC.
    expect(lastMonth(at("2026-09-30", "23:30:00"))).toEqual({ from: "2026-08-01", to: "2026-08-31" });
  });

  it("every preset is a range the API accepts", () => {
    for (const now of [at("2026-01-01"), at("2026-05-31"), at("2026-12-31")]) {
      for (const r of [lastMonth(now), lastQuarter(now)]) expect(rangeError(r.from, r.to)).toBeNull();
    }
  });
});

describe("rangeError", () => {
  it("accepts a one-day range and the longest range", () => {
    expect(rangeError("2026-10-01", "2026-10-01")).toBeNull();
    expect(rangeError("2025-10-01", "2026-10-01")).toBeNull(); // 366 days
  });

  it("refuses a range that is not complete or not real days", () => {
    expect(rangeError("", "2026-10-01")).toMatch(/start and an end/);
    expect(rangeError("2026-10-01", "")).toMatch(/start and an end/);
    expect(rangeError("2026-02-30", "2026-03-05")).toMatch(/start and an end/);
  });

  it("refuses an end before the start", () => {
    expect(rangeError("2026-10-03", "2026-10-01")).toMatch(/before the start/);
  });

  it(`refuses more than ${MAX_REPORT_DAYS} days`, () => {
    expect(rangeError("2025-09-30", "2026-10-01")).toMatch(/at most 366/);
  });
});

describe("isDay", () => {
  it("accepts real days only", () => {
    expect(isDay("2028-02-29")).toBe(true);
    expect(isDay("2026-02-29")).toBe(false);
    expect(isDay("2026-2-9")).toBe(false);
    expect(isDay("tomorrow")).toBe(false);
  });
});

describe("includesToday", () => {
  it("is true when the range ends today (UTC) or later", () => {
    expect(includesToday("2026-10-17", at("2026-10-17", "00:00:01"))).toBe(true);
    expect(includesToday("2026-10-20", at("2026-10-17"))).toBe(true);
  });

  it("is false when the range ended before today", () => {
    expect(includesToday("2026-10-16", at("2026-10-17"))).toBe(false);
  });
});

describe("reportFilename", () => {
  it("puts the range in the name, as the Worker does", () => {
    expect(reportFilename({ from: "2026-07-01", to: "2026-09-30" })).toBe("royalty-report-2026-07-01_to_2026-09-30.csv");
  });
});
