import { env } from "cloudflare:workers";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { EVENTS_KEEP_DAYS, runScheduled } from "../src/cron/rollups";
import { installFirebaseJwks, player, removeFirebaseJwks } from "./helpers";

beforeAll(installFirebaseJwks);
afterAll(removeFirebaseJwks);

const DAY = 86_400_000;
const NOW = Date.now();

const round = (trackId: number, points: number, correct: boolean) => ({
  trackId,
  question: "song",
  optionIds: [trackId, trackId + 1, trackId + 2, trackId + 3],
  chosenId: trackId,
  responseMs: 3000,
  hintUsed: false,
  points,
  correct,
  valid: true,
});
const EVENTS = { clientEndedAt: 123, rounds: [round(1, 120, true), round(5, 0, false)], ads: { interstitialShown: 2, rewardedCompleted: 1 } };

async function seed(id: string, ageDays: number) {
  await env.DB.prepare("INSERT OR IGNORE INTO users (id, is_anonymous, created_at) VALUES ('trim-user', 0, 0)").run();
  await env.DB.prepare(
    `INSERT INTO game_sessions (id, user_id, mode, generation_id, difficulty, received_at, rounds, score, track_ids_json, events_json)
     VALUES (?1, 'trim-user', 'intro', 0, 'easy', ?2, 2, 120, '[1,5]', ?3)`,
  )
    .bind(id, NOW - ageDays * DAY, JSON.stringify(EVENTS))
    .run();
}
const events = async (id: string) =>
  JSON.parse((await env.DB.prepare("SELECT events_json FROM game_sessions WHERE id = ?1").bind(id).first<{ events_json: string }>())!.events_json);

describe("trimming events_json after 90 days", () => {
  it("keeps only track, points and correctness per round, and the ads; leaves newer and much older sessions", async () => {
    const old = "00000000-0000-4000-8000-000000000091";
    await seed(old, EVENTS_KEEP_DAYS + 1);
    await seed("trim-recent", EVENTS_KEEP_DAYS - 1);
    // Outside the 7-day band the run looks at (it would have been trimmed by an earlier night).
    await seed("trim-ancient", EVENTS_KEEP_DAYS + 30);
    await runScheduled(env, NOW);

    expect(await events(old)).toEqual({
      clientEndedAt: 123,
      rounds: [
        { trackId: 1, points: 120, correct: true },
        { trackId: 5, points: 0, correct: false },
      ],
      ads: { interstitialShown: 2, rewardedCompleted: 1 },
      trimmed: true,
    });
    expect(await events("trim-recent")).toEqual(EVENTS);
    expect(await events("trim-ancient")).toEqual(EVENTS);

    // A second night changes nothing.
    await runScheduled(env, NOW);
    expect((await events(old)).rounds).toHaveLength(2);

    // A replay of the trimmed session still gets its stored result.
    const res = await player("trim-user", "/v1/sessions", {
      method: "POST",
      body: {
        id: old,
        mode: "intro",
        generationId: 0,
        difficulty: "easy",
        clientStartedAt: 0,
        clientEndedAt: 123,
        offline: true,
        rounds: [round(1, 0, true), round(5, 0, false)].map(({ points: _p, correct: _c, valid: _v, ...r }) => r),
        ads: { interstitialShown: 2, rewardedCompleted: 1 },
      },
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      score: 120,
      rounds: [
        { points: 120, correct: true },
        { points: 0, correct: false },
      ],
      flagged: false,
    });
  });
});
