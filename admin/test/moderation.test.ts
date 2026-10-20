import { describe, expect, it } from "vitest";
import { BUCKETS, anomalyDays, anomalyRules, flagLabels, median, nameReportDetails, noteProblem, responseHistogram, ruleLabel } from "../src/lib/moderation";

describe("noteProblem", () => {
  it("requires a note that is not only spaces", () => {
    expect(noteProblem("")).toMatch(/required/);
    expect(noteProblem("   \n ")).toMatch(/required/);
    expect(noteProblem(" ok ")).toBeNull();
  });

  it("allows 500 characters and no more, counted after trimming", () => {
    expect(noteProblem("x".repeat(500))).toBeNull();
    expect(noteProblem(` ${"x".repeat(500)} `)).toBeNull();
    expect(noteProblem("x".repeat(501))).toMatch(/500/);
  });
});

describe("responseHistogram", () => {
  it("counts into 0.5 s buckets with a last bucket for 10 s and slower", () => {
    const h = responseHistogram([0, 499, 500, 1250, 9999, 10_000, 40_000]);
    expect(h).toHaveLength(BUCKETS + 1);
    expect(h[0]).toEqual({ label: "0.0–0.5 s", count: 2 });
    expect(h[1]!.count).toBe(1);
    expect(h[2]!.count).toBe(1);
    expect(h[19]).toEqual({ label: "9.5–10.0 s", count: 1 });
    expect(h[20]).toEqual({ label: "10.0 s+", count: 2 });
    expect(h.reduce((n, b) => n + b.count, 0)).toBe(7);
  });

  it("leaves out unanswered rounds and nonsense", () => {
    expect(responseHistogram([null, -5, Number.NaN]).every((b) => b.count === 0)).toBe(true);
    expect(responseHistogram([]).every((b) => b.count === 0)).toBe(true);
  });
});

describe("median", () => {
  it("takes the middle, or the mean of the two middle values", () => {
    expect(median([])).toBeNull();
    expect(median([5])).toBe(5);
    expect(median([9, 1, 5])).toBe(5);
    expect(median([4, 1, 3, 2])).toBe(2.5);
  });
});

describe("anomaly details", () => {
  const details = {
    days: {
      "2026-10-15": { rules: ["session_flood"], sessions: 25 },
      "2026-10-14": { rules: ["bot_regularity", "inhuman_accuracy"], accuracy: 0.99 },
      "2026-10-16": { rules: ["bot_regularity"] },
    },
  };

  it("lists each rule once, in the order the days came", () => {
    expect(anomalyRules(details)).toEqual(["bot_regularity", "inhuman_accuracy", "session_flood"]);
  });

  it("lists the days oldest first with their metrics", () => {
    expect(anomalyDays(details).map((d) => d.date)).toEqual(["2026-10-14", "2026-10-15", "2026-10-16"]);
    expect(anomalyDays(details)[1]!.metrics.sessions).toBe(25);
  });

  it("reads details it does not know as empty", () => {
    for (const bad of [null, undefined, "x", 3, {}, { days: 5 }, { days: { d: { rules: "no" } } }]) {
      expect(anomalyRules(bad)).toEqual([]);
    }
    expect(anomalyDays(null)).toEqual([]);
  });
});

describe("labels", () => {
  it("names known rules and flags, and shows unknown ones as they are", () => {
    expect(ruleLabel("session_flood")).toMatch(/sessions/);
    expect(ruleLabel("new_rule")).toBe("new_rule");
    expect(flagLabels(null)).toEqual([]);
    expect(flagLabels("late_answer,voided")).toEqual(["Answer after the window", "Voided by an admin"]);
    expect(flagLabels("brand_new")).toEqual(["brand_new"]);
  });
});

describe("nameReportDetails", () => {
  it("reads the reported name, the counts and the last report", () => {
    expect(nameReportDetails({ displayName: "Bad Name", reports: 3, reporters: ["a", "b"], lastReportedAt: 5 })).toEqual({
      reportedName: "Bad Name",
      reports: 3,
      reporters: 2,
      lastReportedAt: 5,
    });
  });

  it("reads details it does not know as empty", () => {
    for (const d of [null, "x", 3, {}, { displayName: 1, reports: "2", reporters: "a" }]) {
      expect(nameReportDetails(d)).toEqual({ reportedName: null, reports: 0, reporters: 0, lastReportedAt: null });
    }
  });
});
