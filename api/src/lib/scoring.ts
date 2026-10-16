// The scoring rules in docs/scoring.md. Mirrors app/lib/features/game/domain/scorer.dart; both run
// against docs/fixtures/scoring.json and must give identical results.
//
// All arithmetic is on non-negative integers, so the app and the server cannot differ through
// floating point. "Round" means round half up.

export const GAME_MODES = ["intro", "middle", "generation"] as const;
export const DIFFICULTIES = ["easy", "medium", "hard"] as const;
export type GameMode = (typeof GAME_MODES)[number];
export type Difficulty = (typeof DIFFICULTIES)[number];

/** A response faster than this is not a human reaction (milliseconds). */
export const MIN_RESPONSE_MS = 200;
/** The answer window is the clip length plus this. */
export const WINDOW_EXTRA_MS = 5000;
/** Points for a correct answer in generation-guess mode. */
export const GENERATION_BASE = 120;
/** Generation-guess mode always uses a 10 s clip, with no difficulty tiers. */
export const GENERATION_CLIP_MS = 10000;

const CLIP_MS: Record<Difficulty, number> = { easy: 10000, medium: 5000, hard: 3000 };
const BASE: Record<Difficulty, number> = { easy: 100, medium: 150, hard: 200 };

export type RoundScore = {
  /** What the round is worth after the hint. 0 when wrong or invalid. */
  points: number;
  base: number;
  bonus: number;
  correct: boolean;
  /** False when the response was faster than a person can react; such a round flags the session. */
  valid: boolean;
  hintHalved: boolean;
};

export type RoundAnswer = { correct: boolean; responseMs: number; hintUsed?: boolean };

export type SessionScore = { rounds: RoundScore[]; total: number; flagged: boolean };

/** Base points before the speed bonus. Middle mode multiplies by 1.25, rounded half up. */
export function basePoints(mode: GameMode, difficulty: Difficulty): number {
  if (mode === "generation") return GENERATION_BASE;
  const base = BASE[difficulty];
  // round(base * 5 / 4) in integers.
  return mode === "middle" ? Math.floor((base * 5 + 2) / 4) : base;
}

/** The time the player has to answer, in milliseconds: clip length plus 5 s. */
export function windowMs(mode: GameMode, difficulty: Difficulty): number {
  return (mode === "generation" ? GENERATION_CLIP_MS : CLIP_MS[difficulty]) + WINDOW_EXTRA_MS;
}

/** `round(0.5 * base * max(0, 1 - responseMs / windowMs))`, half up, in integers. */
export function speedBonus(base: number, responseMs: number, window: number): number {
  if (responseMs >= window) return 0;
  return Math.floor((base * (window - responseMs) + window) / (2 * window));
}

export function scoreRound(
  mode: GameMode,
  difficulty: Difficulty,
  { correct, responseMs, hintUsed = false }: RoundAnswer,
): RoundScore {
  const base = basePoints(mode, difficulty);
  if (responseMs < MIN_RESPONSE_MS) {
    return { points: 0, base, bonus: 0, correct, valid: false, hintHalved: false };
  }
  if (!correct) {
    return { points: 0, base, bonus: 0, correct: false, valid: true, hintHalved: false };
  }
  const bonus = speedBonus(base, responseMs, windowMs(mode, difficulty));
  const full = base + bonus;
  // A hint halves the points: round(full / 2), half up.
  const points = hintUsed ? Math.floor((full + 1) / 2) : full;
  return { points, base, bonus, correct: true, valid: true, hintHalved: hintUsed };
}

export function scoreSession(mode: GameMode, difficulty: Difficulty, answers: readonly RoundAnswer[]): SessionScore {
  const rounds = answers.map((a) => scoreRound(mode, difficulty, a));
  return {
    rounds,
    total: rounds.reduce((sum, r) => sum + r.points, 0),
    flagged: rounds.some((r) => !r.valid),
  };
}
