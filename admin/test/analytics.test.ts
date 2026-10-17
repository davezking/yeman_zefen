import { describe, expect, it } from "vitest";
import type { DayStats } from "../src/api/analytics";
import { TARGETS, axisLabel, kpis, lastDays, overallRetention, percent, retentionByWeek, weekStart } from "../src/lib/analytics";

const day = (date: string, o: Partial<DayStats> = {}): DayStats => ({
  date,
  rolledUp: true,
  dau: 0,
  newUsers: 0,
  sessions: 0,
  rounds: 0,
  roundsPerSession: 0,
  retained: { d1: null, d7: null, d30: null },
  interstitialsShown: 0,
  rewardedCompleted: 0,
  ...o,
});

describe("weekStart", () => {
  it("is the Monday of the week", () => {
    expect(weekStart("2026-10-12")).toBe("2026-10-12"); // a Monday
    expect(weekStart("2026-10-18")).toBe("2026-10-12"); // the Sunday after it
    expect(weekStart("2026-10-19")).toBe("2026-10-19");
    expect(weekStart("2026-01-01")).toBe("2025-12-29");
  });
});

describe("retention", () => {
  const days = [
    day("2026-10-12", { newUsers: 10, retained: { d1: 4, d7: 2, d30: null } }),
    day("2026-10-13", { newUsers: 30, retained: { d1: 9, d7: 3, d30: null } }),
    day("2026-10-14", { newUsers: 20, retained: { d1: 5, d7: null, d30: null } }),
    day("2026-10-19", { newUsers: 5, retained: { d1: null, d7: null, d30: null } }),
  ];

  it("weights by cohort size rather than averaging the days' percentages", () => {
    // D1: (4 + 9 + 5) / (10 + 30 + 20) = 0.3; an average of 40 %, 30 %, 25 % would say 31.7 %.
    expect(overallRetention(days, "d1")).toBeCloseTo(0.3);
  });

  it("leaves out cohorts whose answer is not known yet, from both sides", () => {
    // D7 is known for the first two cohorts only: (2 + 3) / (10 + 30).
    expect(overallRetention(days, "d7")).toBeCloseTo(5 / 40);
    expect(overallRetention(days, "d30")).toBeNull();
  });

  it("groups cohorts by week", () => {
    const [w1, w2] = retentionByWeek(days);
    expect(w1).toMatchObject({ week: "2026-10-12", newUsers: 60 });
    expect(w1!.d1).toBeCloseTo(0.3);
    expect(w2).toMatchObject({ week: "2026-10-19", newUsers: 5, d1: null, d7: null, d30: null });
  });

  it("leaves out a cohort whose own day is not rolled up: its new users are unknown", () => {
    // Day C failed to roll up, but C+1 did and wrote C's D1 count; adding it over 0 new users would inflate the share.
    const list = [
      day("2026-10-12", { newUsers: 10, retained: { d1: 3, d7: null, d30: null } }),
      day("2026-10-13", { rolledUp: false, retained: { d1: 12, d7: null, d30: null } }),
    ];
    expect(overallRetention(list, "d1")).toBeCloseTo(0.3);
  });

  it("says how many days of a week are inside the range", () => {
    const [w1, w2] = retentionByWeek([day("2026-10-17"), day("2026-10-18"), day("2026-10-19")]);
    expect(w1).toMatchObject({ week: "2026-10-12", days: 2 });
    expect(w2).toMatchObject({ week: "2026-10-19", days: 1 });
  });

  it("a known 0 is 0 %, not a dash", () => {
    expect(overallRetention([day("2026-10-12", { newUsers: 8, retained: { d1: 0, d7: null, d30: null } })], "d1")).toBe(0);
    expect(percent(0)).toBe("0.0 %");
    expect(percent(null)).toBe("–");
  });
});

describe("kpis", () => {
  const get = (list: ReturnType<typeof kpis>, key: string) => list.find((k) => k.key === key)!;

  it("shows each KPI against its target and whether it is met", () => {
    const list = kpis([
      day("2026-10-12", { newUsers: 100, dau: 900, sessions: 100, rounds: 1600, retained: { d1: 40, d7: 10, d30: 6 } }),
      day("2026-10-13", { newUsers: 100, dau: 1200, sessions: 100, rounds: 1600, retained: { d1: 30, d7: 20, d30: null } }),
    ]);
    expect(get(list, "d1")).toMatchObject({ value: 0.35, target: TARGETS.d1, status: "met" }); // exactly on target is met
    expect(get(list, "d7")).toMatchObject({ value: 0.15, status: "met" });
    expect(get(list, "d30")).toMatchObject({ value: 0.06, status: "met" });
    expect(get(list, "dau")).toMatchObject({ value: 1200, status: "met" }); // the latest day
    expect(get(list, "roundsPerSession")).toMatchObject({ value: 16, status: "met" });
  });

  it("marks a figure under its target as missed", () => {
    const list = kpis([day("2026-10-12", { newUsers: 100, dau: 40, sessions: 10, rounds: 100, retained: { d1: 20, d7: null, d30: null } })]);
    expect(get(list, "d1")).toMatchObject({ value: 0.2, status: "missed" });
    expect(get(list, "dau").status).toBe("missed");
    expect(get(list, "roundsPerSession")).toMatchObject({ value: 10, status: "missed" });
  });

  it("says unknown, not missed, when there is nothing to measure", () => {
    const list = kpis([day("2026-10-12", { rolledUp: false })]);
    for (const k of list) expect(k).toMatchObject({ value: null, status: "unknown" });
  });

  it("ignores days that are not rolled up", () => {
    const list = kpis([
      day("2026-10-12", { dau: 2000, sessions: 10, rounds: 200 }),
      day("2026-10-13", { rolledUp: false }),
    ]);
    expect(get(list, "dau").value).toBe(2000);
    expect(get(list, "roundsPerSession").value).toBe(20);
  });
});

describe("axisLabel", () => {
  it("drops the year only when the range is within one year", () => {
    expect(axisLabel("2026-10-17", { from: "2026-01-01", to: "2026-12-31" })).toBe("10-17");
    expect(axisLabel("2026-10-17", { from: "2025-10-17", to: "2026-10-17" })).toBe("2026-10-17");
  });
});

describe("lastDays", () => {
  it("ends yesterday and spans n days", () => {
    expect(lastDays(Date.parse("2026-10-17T05:00:00Z"), 7)).toEqual({ from: "2026-10-10", to: "2026-10-16" });
    expect(lastDays(Date.parse("2026-10-17T05:00:00Z"), 1)).toEqual({ from: "2026-10-16", to: "2026-10-16" });
  });
});
