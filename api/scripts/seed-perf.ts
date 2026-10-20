// Fill an EMPTY database with realistic volume for the load test (docs/perf.md):
//   1,000 tracks, 20,000 users, 300,000 game sessions and 8 weeks of leaderboard rows.
//
//   npx tsx scripts/seed-perf.ts --db yz-db-staging --env staging --remote
//   npx tsx scripts/seed-perf.ts --db yz-db --local --sessions 30000     (a smaller local run)
//
// The rows are generated inside D1 by recursive CTEs, so only a few KB of SQL travel; the
// sessions go in chunks to stay under D1's per-query time limit. Numbers are derived from the row
// index (no randomness), so two runs make the same data. It refuses to run on a database that
// already has tracks, so it can never touch real data by accident.
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isoWeek } from "../src/lib/period";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(`--${name}`);
const value = (name: string, fallback: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1]! : fallback;
};

const db = value("db", "yz-db-staging");
const env = value("env", "");
const remote = flag("remote");
if (!remote && !flag("local")) {
  console.error("Say where: --local or --remote");
  process.exit(1);
}
// Without --env, wrangler takes the top-level database, whose name (yz-db) is also prod's.
if (remote && env !== "staging") {
  console.error("--remote is only for staging: add --env staging (and --db yz-db-staging).");
  process.exit(1);
}
const TRACKS = 1000;
const ARTISTS = 150;
const USERS = 20_000;
const SESSIONS = Number(value("sessions", "300000"));
const CHUNK = 25_000;
const WEEKS = 8;
const DAY_MS = 86_400_000;
const now = Date.now();

const dir = mkdtempSync(join(tmpdir(), "seed-perf-"));
let n = 0;
function run(sql: string, label: string): string {
  const file = join(dir, `${String(++n).padStart(3, "0")}.sql`);
  writeFileSync(file, sql);
  const out = execFileSync(
    "npx",
    ["wrangler", "d1", "execute", db, remote ? "--remote" : "--local", ...(env ? ["--env", env] : []), "--file", file, "--yes", "--json"],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  console.log(`ok ${label}`);
  return out;
}

// A cheap integer hash of the row index: spreads values without a random source.
const H = (i: string, salt: number) => `((${i} * 2654435761 + ${salt} * 40503) % 4294967296)`;
const series = (count: number, from = 1) =>
  `WITH RECURSIVE n(i) AS (SELECT ${from} UNION ALL SELECT i + 1 FROM n WHERE i < ${from + count - 1})`;

// Refuse a database that already has a catalog.
const existing = JSON.parse(run("SELECT COUNT(*) AS n FROM tracks;", "check the database is empty")) as { results: { n: number }[] }[];
if ((existing[0]?.results[0]?.n ?? 1) > 0) {
  console.error("This database already has tracks. seed-perf only fills an empty database.");
  process.exit(1);
}

run(
  `${series(ARTISTS)}
   INSERT INTO artists (name_am, name_latin, created_at, updated_at)
   SELECT 'አርቲስት ' || i, 'Artist ' || i, ${now}, ${now} FROM n;
   ${series(TRACKS)}
   INSERT INTO tracks (artist_id, title_am, title_latin, release_year, generation_id, status, created_at, updated_at)
   SELECT (SELECT MIN(id) FROM artists) + ${H("i", 1)} % ${ARTISTS}, 'ዘፈን ' || i, 'Song ' || i,
          1960 + ${H("i", 2)} % 65, 1 + ${H("i", 3)} % 5, 'approved', ${now}, ${now} FROM n;
   -- Five published packs, one per era (what GET /v1/packs lists).
   ${series(5)}
   INSERT INTO packs (slug, name_am, name_en, generation_id, genre_id, current_version)
   SELECT 'perf-era-' || i, 'ጥቅል ' || i, 'Pack ' || i, i, NULL, 1 FROM n;
   INSERT INTO pack_versions (pack_id, version, manifest_key, track_count, total_bytes, published_at)
   SELECT id, 1, 'packs/' || slug || '/1/manifest.json', 200, 66000000, ${now} FROM packs;`,
  `${ARTISTS} artists, ${TRACKS} tracks, 5 packs`,
);

run(
  `${series(USERS)}
   INSERT INTO users (id, display_name, is_anonymous, country, created_at, last_seen_at, shadow_banned)
   SELECT printf('perf-u-%05d', i),
          CASE WHEN ${H("i", 4)} % 10 < 6 THEN 'Player ' || i END,
          CASE WHEN ${H("i", 4)} % 10 < 6 THEN 0 ELSE 1 END,
          CASE ${H("i", 5)} % 10 WHEN 0 THEN 'US' WHEN 1 THEN 'GB' WHEN 2 THEN 'DE' ELSE 'ET' END,
          ${now} - (${H("i", 6)} % 60) * ${DAY_MS}, ${now} - (${H("i", 7)} % 14) * ${DAY_MS},
          CASE WHEN i % 200 = 0 THEN 1 ELSE 0 END
     FROM n;`,
  `${USERS} users (60% registered)`,
);

// One session is ~10 rounds and ~1 KB of events, like a real one.
const ROUND = `{"trackId":1,"question":"song","optionIds":[1,2,3,4],"chosenId":1,"responseMs":3100,"hintUsed":false,"points":120,"correct":true,"valid":true}`;
const EVENTS_JSON = `{"clientEndedAt":0,"rounds":[${Array.from({ length: 10 }, () => ROUND).join(",")}],"ads":{"interstitialShown":1,"rewardedCompleted":0}}`;
JSON.parse(EVENTS_JSON); // fail here, not in D1, if the template is ever broken
for (let from = 1; from <= SESSIONS; from += CHUNK) {
  const count = Math.min(CHUNK, SESSIONS - from + 1);
  run(
    `${series(count, from)}
     INSERT INTO game_sessions (id, user_id, mode, generation_id, difficulty, client_started_at, received_at, rounds, score,
                                track_ids_json, events_json, offline, country, flagged)
     SELECT printf('perf-s-%07d', i), printf('perf-u-%05d', 1 + ${H("i", 8)} % ${USERS}),
            CASE ${H("i", 9)} % 3 WHEN 0 THEN 'intro' WHEN 1 THEN 'middle' ELSE 'generation' END, 0,
            CASE ${H("i", 10)} % 3 WHEN 0 THEN 'easy' WHEN 1 THEN 'medium' ELSE 'hard' END,
            ${now} - (${H("i", 11)} % ${WEEKS * 7}) * ${DAY_MS} - 120000, ${now} - (${H("i", 11)} % ${WEEKS * 7}) * ${DAY_MS},
            10, 200 + ${H("i", 12)} % 1300, '[1,2,3,4,5,6,7,8,9,10]',
            '${EVENTS_JSON.replaceAll("'", "''")}',
            ${H("i", 13)} % 10 = 0, 'ET', 0
       FROM n;`,
    `sessions ${from}..${from + count - 1}`,
  );
}

// Leaderboards: everyone registered is on the all-time boards; about a third play in any given week.
const weeks = Array.from({ length: WEEKS }, (_, k) => isoWeek(now - k * 7 * DAY_MS));
run(
  `INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
   SELECT 'all', 0, id, 500 + (CAST(substr(id, 8) AS INTEGER) * 7919) % 90000, ${now} FROM users WHERE is_anonymous = 0;
   INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
   SELECT 'all', 1 + (CAST(substr(id, 8) AS INTEGER) * 31) % 5, id, 300 + (CAST(substr(id, 8) AS INTEGER) * 104729) % 60000, ${now}
     FROM users WHERE is_anonymous = 0 AND CAST(substr(id, 8) AS INTEGER) % 5 < 3;
   WITH w(period, k) AS (VALUES ${weeks.map((w, k) => `('${w}', ${k})`).join(", ")})
   INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
   SELECT w.period, 0, u.id, 100 + (CAST(substr(u.id, 8) AS INTEGER) * 6007 + w.k * 811) % 20000, ${now} - w.k * 7 * ${DAY_MS}
     FROM w JOIN users u ON u.is_anonymous = 0 AND (CAST(substr(u.id, 8) AS INTEGER) + w.k * 7) % 3 = 0;
   WITH w(period, k) AS (VALUES ${weeks.map((w, k) => `('${w}', ${k})`).join(", ")})
   INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
   SELECT w.period, 1 + (CAST(substr(u.id, 8) AS INTEGER) + w.k) % 5, u.id, 80 + (CAST(substr(u.id, 8) AS INTEGER) * 4243 + w.k * 377) % 15000, ${now} - w.k * 7 * ${DAY_MS}
     FROM w JOIN users u ON u.is_anonymous = 0 AND (CAST(substr(u.id, 8) AS INTEGER) + w.k * 7) % 3 = 0;`,
  `leaderboard rows for 'all' and ${WEEKS} weeks (${weeks.join(", ")})`,
);

try {
  run("ANALYZE;", "ANALYZE (gives the query planner row counts)");
} catch {
  console.warn("ANALYZE was refused here; D1 runs PRAGMA optimize on its own.");
}
console.log("Done. Check the counts with: SELECT COUNT(*) FROM game_sessions;");
