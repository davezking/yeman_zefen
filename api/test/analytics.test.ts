import { env } from "cloudflare:workers";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { rollUpDay } from "../src/cron/rollups";
import { buildCountries, buildDays } from "../src/lib/analytics";
import { adminWithQueryCount, api, installTestJwks, removeTestJwks, seedAdmins } from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
afterAll(removeTestJwks);

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM game_sessions"),
    env.DB.prepare("DELETE FROM ad_events_daily"),
    env.DB.prepare("DELETE FROM royalty_daily"),
    env.DB.prepare("DELETE FROM analytics_daily"),
    env.DB.prepare("DELETE FROM users WHERE id <> 'deleted'"),
  ]);
});

const at = (iso: string) => Date.parse(iso);
let n = 0;
const user = (id: string, createdAt: string) =>
  env.DB.prepare("INSERT INTO users (id, is_anonymous, created_at) VALUES (?1, 1, ?2)").bind(id, at(createdAt)).run();
const play = (userId: string, receivedAt: string, o: { country?: string; rounds?: number } = {}) =>
  env.DB.prepare(
    `INSERT INTO game_sessions (id, user_id, mode, received_at, rounds, score, track_ids_json, events_json, country, flagged)
     VALUES (?1, ?2, 'song', ?3, ?4, 0, '[]', '{}', ?5, 0)`,
  )
    .bind(`a${++n}`, userId, at(receivedAt), o.rounds ?? 10, o.country ?? "ET")
    .run();
const retention = async (cohort: string) =>
  Object.fromEntries(
    (
      await env.DB.prepare("SELECT metric, value FROM analytics_daily WHERE date = ?1 AND metric LIKE 'retention_%'").bind(cohort).all<{
        metric: string;
        value: number;
      }>()
    ).results.map((r) => [r.metric, r.value]),
  );

/**
 * Hand-checked cohort: users created on 2026-10-01 are a, b, c, d (c at the last millisecond of the day).
 *   a plays on the 2nd (D1) and the 8th (D7), twice on the 8th; b plays on the 8th (D7);
 *   c plays on the 31st (D30); d never plays. e is created on the 2nd, so a different cohort, at 00:00:00.000.
 */
async function seedCohort() {
  await user("a", "2026-10-01T08:00:00Z");
  await user("b", "2026-10-01T09:00:00Z");
  await user("c", "2026-10-01T23:59:59.999Z");
  await user("d", "2026-10-01T10:00:00Z");
  await user("e", "2026-10-02T00:00:00.000Z");
  await play("a", "2026-10-02T12:00:00Z");
  await play("a", "2026-10-08T07:00:00Z");
  await play("a", "2026-10-08T19:00:00Z");
  await play("b", "2026-10-08T12:00:00Z");
  await play("c", "2026-10-31T12:00:00Z");
  await play("e", "2026-10-03T12:00:00Z");
  await play("e", "2026-10-02T12:00:00Z"); // the cohort's own day does not count as retention
}

describe("retention in the nightly roll-up", () => {
  it("counts the cohort's users who played 1, 7 and 30 days later (hand-checked)", async () => {
    await seedCohort();
    for (const d of ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-08", "2026-10-31"]) await rollUpDay(env, d);

    // Cohort 10-01: D1 = {a}, D7 = {a, b} (a counted once), D30 = {c}.
    expect(await retention("2026-10-01")).toEqual({ retention_d1: 1, retention_d7: 2, retention_d30: 1 });
    // Cohort 10-02 is {e}; e plays on the 3rd. Its D7 and D30 days are not rolled up yet.
    expect(await retention("2026-10-02")).toEqual({ retention_d1: 1 });
    // new_users is the denominator.
    const nu = await env.DB.prepare("SELECT value FROM analytics_daily WHERE date = '2026-10-01' AND metric = 'new_users'").first<{ value: number }>();
    expect(nu?.value).toBe(4);
  });

  it("writes 0 (not nothing) for a cohort nobody came back to, once the day is rolled up", async () => {
    await user("a", "2026-10-01T08:00:00Z");
    await rollUpDay(env, "2026-10-02");
    expect(await retention("2026-10-01")).toEqual({ retention_d1: 0 });
  });

  it("a re-run of the cohort's own day keeps its retention rows", async () => {
    await seedCohort();
    await rollUpDay(env, "2026-10-02");
    await rollUpDay(env, "2026-10-01");
    expect(await retention("2026-10-01")).toEqual({ retention_d1: 1 });
    await rollUpDay(env, "2026-10-02"); // and re-running the later day gives the same answer
    expect(await retention("2026-10-01")).toEqual({ retention_d1: 1 });
  });

  it("never counts the deleted placeholder as a cohort member", async () => {
    await env.DB.prepare("UPDATE users SET created_at = ?1 WHERE id = 'deleted'").bind(at("2026-10-01T05:00:00Z")).run();
    await play("deleted", "2026-10-02T05:00:00Z");
    await rollUpDay(env, "2026-10-02");
    expect(await retention("2026-10-01")).toEqual({ retention_d1: 0 });
  });
});

describe("GET /admin/analytics", () => {
  const get = (q: string) => api(`/admin/analytics?${q}`);

  it("returns a series with one entry per day, rolled up or not", async () => {
    await user("a", "2026-10-01T08:00:00Z");
    await play("a", "2026-10-01T09:00:00Z", { rounds: 15 });
    await play("a", "2026-10-01T10:00:00Z", { rounds: 10 });
    await play("a", "2026-10-02T10:00:00Z", { rounds: 5 });
    await rollUpDay(env, "2026-10-01");
    await rollUpDay(env, "2026-10-02");
    const body = await (await get("from=2026-10-01&to=2026-10-03")).json<{ days: ReturnType<typeof buildDays> }>();

    expect(body.days.map((d) => d.date)).toEqual(["2026-10-01", "2026-10-02", "2026-10-03"]);
    expect(body.days[0]).toMatchObject({
      rolledUp: true, dau: 1, newUsers: 1, sessions: 2, rounds: 25, roundsPerSession: 12.5,
      retained: { d1: 1, d7: null, d30: null },
    });
    expect(body.days[1]).toMatchObject({ dau: 1, newUsers: 0, sessions: 1, roundsPerSession: 5 });
    expect(body.days[2]).toMatchObject({ rolledUp: false, dau: 0, sessions: 0 });
  });

  it("sums plays by country and the diaspora share", async () => {
    await user("a", "2026-10-01T08:00:00Z");
    await env.DB.batch(
      [["ET", 60], ["US", 25], ["SE", 5], ["XX", 10]].map(([c, v]) =>
        env.DB.prepare("INSERT INTO analytics_daily (date, metric, dimension, value) VALUES ('2026-10-01', 'plays_by_country', ?1, ?2)").bind(c, v),
      ),
    );
    const body = await (await get("from=2026-10-01&to=2026-10-01")).json<{ countries: ReturnType<typeof buildCountries> }>();
    expect(body.countries.top.map((r) => r.country)).toEqual(["ET", "US", "SE"]);
    expect(body.countries).toMatchObject({ placed: 90, unknown: 10 });
    expect(body.countries.diasporaShare).toBeCloseTo(30 / 90);
  });

  it("returns ad impressions and rewarded completions per day", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO ad_events_daily (date, country, format, event, count) VALUES ('2026-10-01', 'ET', 'interstitial', 'shown', 4)"),
      env.DB.prepare("INSERT INTO ad_events_daily (date, country, format, event, count) VALUES ('2026-10-01', 'US', 'interstitial', 'shown', 3)"),
      env.DB.prepare("INSERT INTO ad_events_daily (date, country, format, event, count) VALUES ('2026-10-01', 'ET', 'rewarded', 'completed', 2)"),
    ]);
    const body = await (await get("from=2026-10-01&to=2026-10-01")).json<{ days: ReturnType<typeof buildDays> }>();
    expect(body.days[0]).toMatchObject({ interstitialsShown: 7, rewardedCompleted: 2 });
  });

  it("an empty range is all zeros, and shares are null", async () => {
    const body = await (await get("from=2026-10-01&to=2026-10-02")).json<{ days: unknown[]; countries: { diasporaShare: null } }>();
    expect(body.days).toHaveLength(2);
    expect(body.countries.diasporaShare).toBeNull();
  });

  it("rejects a bad or too long range", async () => {
    expect((await get("from=2026-10-05&to=2026-10-01")).status).toBe(400);
    expect((await get("from=2026-13-01&to=2026-10-01")).status).toBe(400);
    expect((await get("from=2025-01-01&to=2026-10-01")).status).toBe(400);
    expect((await get("")).status).toBe(400);
  });

  it("is three D1 queries plus the admin check, whatever the range holds", async () => {
    const { response, queries } = await adminWithQueryCount("/admin/analytics?from=2026-01-01&to=2026-10-01");
    expect(response.status).toBe(200);
    expect(queries).toBe(4);
  });
});
