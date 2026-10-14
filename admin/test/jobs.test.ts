import { describe, expect, it } from "vitest";
import { duration, errorList, isActive, summaryText } from "../src/lib/jobs";

describe("job display helpers", () => {
  it("knows which jobs are still moving", () => {
    expect(["queued", "running"].every(isActive)).toBe(true);
    expect(["succeeded", "failed"].some(isActive)).toBe(false);
  });
  it("formats durations, counting up for a running job", () => {
    expect(duration(null, null, 5000)).toBe("–");
    expect(duration(1000, 43_000, 0)).toBe("42 s");
    expect(duration(0, 185_000, 0)).toBe("3 min 05 s");
    expect(duration(1000, null, 11_000)).toBe("10 s");
  });
  it("summarises counts and errors", () => {
    expect(summaryText({ scraped: 10, created: 4, flagged: 2, errors: ["x"] })).toBe("scraped 10, created 4, flagged 2");
    expect(summaryText({ error: "GitHub returned 404" })).toBe("error: GitHub returned 404");
    expect(summaryText(null)).toBe("");
  });
  it("lists a failed run's error messages", () => {
    expect(errorList({ errors: ["a", 3, "b"] })).toEqual(["a", "b"]);
    expect(errorList({})).toEqual([]);
  });
});
