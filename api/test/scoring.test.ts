import { describe, expect, it } from "vitest";
import fixtures from "../../docs/fixtures/scoring.json";
import scoringDoc from "../../docs/scoring.md?raw";
import { isoWeek } from "../src/lib/period";
import { basePoints, scoreRound, scoreSession, windowMs, type Difficulty, type GameMode } from "../src/lib/scoring";

// The same fixture runs against the app's Scorer (app/test/features/game/domain/scorer_test.dart):
// both sides must agree on every case.
type RoundCase = (typeof fixtures.rounds)[number];
type SessionCase = (typeof fixtures.sessions)[number];

// Generation mode ignores difficulty; the fixture says so with null.
const difficultyOf = (d: string | null): Difficulty => (d ?? "easy") as Difficulty;

describe("shared scoring fixture: rounds", () => {
  it("has every worked example", () => {
    expect(fixtures.rounds.map((r) => r.id)).toEqual(Array.from({ length: 20 }, (_, i) => `E${i + 1}`));
  });

  it.each(fixtures.rounds)("$id", (c: RoundCase) => {
    const mode = c.mode as GameMode;
    const difficulty = difficultyOf(c.difficulty);
    const score = scoreRound(mode, difficulty, { correct: c.correct, responseMs: c.responseMs, hintUsed: c.hintUsed });
    expect(score.points).toBe(c.points);
    expect(score.valid).toBe(c.valid);
    expect(basePoints(mode, difficulty)).toBe(c.base);
    expect(windowMs(mode, difficulty)).toBe(c.windowMs);
    if (c.valid && c.correct) expect(score.bonus).toBe(c.bonus);
  });
});

describe("shared scoring fixture: sessions", () => {
  it.each(fixtures.sessions)("$id", (c: SessionCase) => {
    const session = scoreSession(c.mode as GameMode, difficultyOf(c.difficulty), c.answers);
    expect(session.rounds.map((r) => r.points)).toEqual(c.points);
    expect(session.total).toBe(c.score);
    expect(session.flagged).toBe(c.flagged);
  });
});

describe("docs/scoring.md", () => {
  it("shows the same worked examples as the fixture", () => {
    const rows = scoringDoc
      .split("\n")
      .filter((line) => /^\| E\d+ \|/.test(line))
      .map((line) => line.split("|").slice(1, -1).map((cell) => cell.trim()));
    const yes = (v: boolean) => (v ? "yes" : "no");
    expect(rows).toEqual(
      fixtures.rounds.map((r) => [
        r.id, r.mode, r.difficulty ?? "-", yes(r.correct), String(r.responseMs), yes(r.hintUsed),
        String(r.base), String(r.windowMs), String(r.bonus), String(r.points), yes(r.valid),
      ]),
    );
  });
});

describe("isoWeek", () => {
  const cases: [string, string][] = [
    ["2026-10-16T12:00:00Z", "2026-W42"],
    ["2026-10-12T00:00:00Z", "2026-W42"], // Monday starts the week
    ["2026-10-11T23:59:59.999Z", "2026-W41"], // Sunday ends the previous one
    ["2021-01-03T12:00:00Z", "2020-W53"], // early January can belong to last year's week 53
    ["2024-12-30T00:00:00Z", "2025-W01"], // late December can belong to next year's week 1
    ["2026-01-01T00:00:00Z", "2026-W01"],
  ];
  it.each(cases)("%s is %s", (iso, week) => {
    expect(isoWeek(Date.parse(iso))).toBe(week);
  });
});
