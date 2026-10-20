// Time the SQL of the three hot routes against a seeded database file (scripts/seed-perf.ts), with
// the same statements the Worker runs. It measures SQLite's own time, not D1's network hop, so it
// finds a missing index or a bad plan; the latency a player sees comes from the k6 run (docs/perf.md).
//
//   npx tsx scripts/sql-bench.ts [path/to/db.sqlite] [iterations]
//
// Session writes run in a transaction that is rolled back, so the seeded data stays as it was.
import { DatabaseSync } from "node:sqlite";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { OWN_SQL, TOP_SQL } from "../src/routes/v1/leaderboard";
import { CATALOG_SQL, LEADERBOARD_SQL, SESSION_SQL, STORED_SQL, USER_TOUCH_SQL } from "../src/routes/v1/sessions";
import { PACKS_SQL } from "../src/routes/v1";
import { isoWeek } from "../src/lib/period";

const D1_DIR = ".wrangler/state/v3/d1/miniflare-D1DatabaseObject";
const defaultFile = () => {
  const f = readdirSync(D1_DIR).find((n) => n.endsWith(".sqlite") && n !== "metadata.sqlite");
  if (!f) throw new Error(`No local D1 database in ${D1_DIR}; run seed-perf.ts --local first`);
  return join(D1_DIR, f);
};
const file = process.argv[2] ?? defaultFile();
const N = Number(process.argv[3] ?? 500);
const db = new DatabaseSync(file);
db.exec("PRAGMA foreign_keys = ON");

const q = (xs: number[], p: number) => xs[Math.min(xs.length - 1, Math.floor((p / 100) * xs.length))]!;
function time(label: string, fn: (i: number) => void): void {
  for (let i = 0; i < 20; i++) fn(i); // warm up the page cache
  const ms: number[] = [];
  for (let i = 0; i < N; i++) {
    const t0 = performance.now();
    fn(i);
    ms.push(performance.now() - t0);
  }
  ms.sort((a, b) => a - b);
  console.log(`${label.padEnd(46)} p50 ${q(ms, 50).toFixed(2)}  p95 ${q(ms, 95).toFixed(2)}  p99 ${q(ms, 99).toFixed(2)}  ms`);
}

const now = Date.now();
const week = isoWeek(now);
const uid = (i: number) => `perf-u-${String(1 + ((i * 7919) % 20000)).padStart(5, "0")}`;

time("packs: list", () => void db.prepare(PACKS_SQL).all());
for (const [period, gen] of [["all", 0], ["all", 3], [week, 0], [week, 3]] as const) {
  time(`leaderboard: top 100 (${period}, era ${gen})`, () => void db.prepare(TOP_SQL).all(period, gen));
}
time("leaderboard/me: own rank (all, era 0)", (i) => void db.prepare(OWN_SQL).all("all", 0, uid(i)));

const ids = (i: number) => Array.from({ length: 10 }, (_, k) => 1 + ((i * 31 + k * 97) % 1000));
time("sessions: the two reads (stored + catalog)", (i) => {
  const t = ids(i);
  db.prepare(STORED_SQL).all(`s-${i}`);
  db.prepare(CATALOG_SQL).all(JSON.stringify(t), "[]", "[]");
});
let n = 0;
time("sessions: the writes (touch + board + row)", (i) => {
  db.exec("BEGIN");
  const id = `bench-${i}-${n++}`;
  const user = uid(i);
  db.prepare(USER_TOUCH_SQL).run(user, 0, "ET", now);
  db.prepare(LEADERBOARD_SQL).run(JSON.stringify(["all", week]), JSON.stringify([0, 1]), 900, now, user, id);
  db.prepare(SESSION_SQL).run(
    id, user, "intro", 1, "medium", now - 120000, now, 10, 900, JSON.stringify(ids(i)), "{}", 0, "ET", 0, null,
  );
  db.exec("ROLLBACK");
});
