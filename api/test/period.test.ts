import { describe, expect, it } from "vitest";
import { currentIsoWeek, isoWeek, periodKey } from "../src/lib/period";

const at = (iso: string) => new Date(`${iso}T12:00:00Z`);

describe("currentIsoWeek", () => {
  const cases: [string, string][] = [
    ["2026-10-16", "2026-W42"],
    ["2026-12-31", "2026-W53"], // Thursday; 2026 has 53 weeks
    ["2027-01-01", "2026-W53"], // Friday, still in 2026's last week
    ["2027-01-03", "2026-W53"], // Sunday
    ["2027-01-04", "2027-W01"], // Monday starts week 1
    ["2024-12-30", "2025-W01"], // Monday of a week holding 2025-01-02
    ["2021-01-03", "2020-W53"],
  ];
  for (const [date, week] of cases) {
    it(`${date} is ${week}`, () => expect(currentIsoWeek(at(date))).toBe(week));
  }

  it("matches isoWeek and defaults to now", () => {
    expect(currentIsoWeek(at("2026-03-01"))).toBe(isoWeek(at("2026-03-01").getTime()));
    expect(currentIsoWeek()).toMatch(/^\d{4}-W\d{2}$/);
  });

  it("changes exactly at Monday 00:00 UTC", () => {
    expect(isoWeek(Date.UTC(2026, 9, 18, 23, 59, 59, 999))).toBe("2026-W42");
    expect(isoWeek(Date.UTC(2026, 9, 19, 0, 0, 0, 0))).toBe("2026-W43");
  });
});

describe("periodKey", () => {
  it("maps the request choice to the stored key", () => {
    const now = at("2026-10-16").getTime();
    expect(periodKey("all", now)).toBe("all");
    expect(periodKey("week", now)).toBe("2026-W42");
  });
});
