// k6 load test for the player API: 70 % leaderboard reads, 20 % session posts, 10 % pack lists.
// How to run, and what the numbers mean: ops/load/README.md and docs/perf.md.
//
//   k6 run -e BASE_URL=https://yz-api-staging.<account>.workers.dev \
//          -e FIREBASE_API_KEY=<dev project web API key> \
//          --summary-trend-stats="avg,med,p(90),p(95),p(99),max" ops/load/mix.js
//
// Players: setup() signs in USERS email/password accounts (perf-<n>@example.com) in the Firebase
// project the staging Worker verifies against (the dev project), creating only the ones that do not
// exist yet: Firebase limits new accounts per IP per hour, so the first run makes them and later runs
// reuse them. Every request carries a real ID token (valid for an hour: keep a run under that). They
// are registered players, so their sessions also write leaderboard rows, which is the expensive path.
import http from "k6/http";
import { check, fail } from "k6";
import { Counter } from "k6/metrics";

const BASE_URL = (__ENV.BASE_URL || "").replace(/\/$/, "");
const API_KEY = __ENV.FIREBASE_API_KEY || "";
const IDENTITY_URL = (__ENV.IDENTITY_URL || "https://identitytoolkit.googleapis.com").replace(/\/$/, "");
// 100 players keep each under the per-player session limit (20 at once, 60 an hour) at the 10x stage.
const USERS = Number(__ENV.USERS || 100);
const PASSWORD = __ENV.PERF_PASSWORD || "perf-load-test-only";
// Track ids seeded by api/scripts/seed-perf.ts on an empty database: 1..1000.
const TRACK_MAX = Number(__ENV.TRACK_MAX || 1000);
// Requests per second for the three stages. 2 rps is the 2,000 DAU peak hour (see docs/perf.md);
// the others are 5x and 10x that.
const BASE_RPS = Number(__ENV.BASE_RPS || 2);
const STAGE_SECONDS = Number(__ENV.STAGE_SECONDS || 300);

if (!BASE_URL) fail("Set -e BASE_URL=https://...");

const stages = [
  { name: "x1", rate: BASE_RPS, startTime: "0s" },
  { name: "x5", rate: BASE_RPS * 5, startTime: `${STAGE_SECONDS + 30}s` },
  { name: "x10", rate: BASE_RPS * 10, startTime: `${(STAGE_SECONDS + 30) * 2}s` },
];

export const options = {
  scenarios: Object.fromEntries(
    stages.map((s) => [
      s.name,
      {
        executor: "constant-arrival-rate",
        rate: s.rate,
        timeUnit: "1s",
        duration: `${STAGE_SECONDS}s`,
        startTime: s.startTime,
        preAllocatedVUs: Math.max(10, s.rate * 2),
        maxVUs: Math.max(50, s.rate * 10),
        env: { STAGE: s.name },
      },
    ]),
  ),
  thresholds: {
    // The targets (docs/architecture.md section 9). 429s are expected only past the per-player limits.
    "http_req_duration{route:packs}": ["p(95)<300"],
    "http_req_duration{route:leaderboard}": ["p(95)<300"],
    "http_req_duration{route:sessions}": ["p(95)<300"],
    "http_req_failed{route:packs}": ["rate<0.01"],
    "http_req_failed{route:leaderboard}": ["rate<0.01"],
    "http_req_failed{route:sessions}": ["rate<0.01"],
  },
};

const rateLimited = new Counter("rate_limited_429");
const flaggedSessions = new Counter("sessions_flagged");

function uuid() {
  const h = "0123456789abcdef";
  let s = "";
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) s += "-";
    else if (i === 14) s += "4";
    else if (i === 19) s += h[8 + Math.floor(Math.random() * 4)];
    else s += h[Math.floor(Math.random() * 16)];
  }
  return s;
}

const int = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));

function identity(method, body) {
  return http.post(`${IDENTITY_URL}/v1/accounts:${method}?key=${API_KEY}`, JSON.stringify({ ...body, returnSecureToken: true }), {
    headers: { "content-type": "application/json" },
    tags: { route: "setup" },
    responseCallback: http.expectedStatuses(200, 400),
  });
}

export function setup() {
  if (!API_KEY) fail("Set -e FIREBASE_API_KEY=... (the Firebase dev project's web API key)");
  const tokens = [];
  let created = 0;
  for (let i = 0; i < USERS; i++) {
    const account = { email: `perf-${i}@example.com`, password: PASSWORD };
    let res = identity("signInWithPassword", account);
    if (res.status !== 200) {
      // An unknown email reads as EMAIL_NOT_FOUND, or INVALID_LOGIN_CREDENTIALS with email enumeration protection on.
      res = identity("signUp", account);
      created++;
    }
    if (res.status !== 200) fail(`player ${i}: ${res.status} ${res.body}`);
    tokens.push(res.json("idToken"));
  }
  console.log(`${USERS} players signed in (${created} created)`);
  return { tokens };
}

function round() {
  const trackId = int(1, TRACK_MAX);
  const options = new Set([trackId]);
  while (options.size < 4) options.add(int(1, TRACK_MAX));
  const optionIds = [...options].sort(() => Math.random() - 0.5);
  // Mostly right, always human-fast enough (>= 200 ms) and inside the answer window.
  const chosenId = Math.random() < 0.7 ? trackId : optionIds.find((id) => id !== trackId);
  return { trackId, question: "song", optionIds, chosenId, responseMs: int(1500, 4500), hintUsed: false };
}

function sessionBody() {
  const now = Date.now();
  return JSON.stringify({
    id: uuid(),
    mode: Math.random() < 0.5 ? "intro" : "middle",
    generationId: 0,
    difficulty: ["easy", "medium", "hard"][int(0, 2)],
    clientStartedAt: now - 120_000,
    clientEndedAt: now - 1_000,
    offline: false,
    rounds: Array.from({ length: 10 }, round),
    ads: { interstitialShown: 1, rewardedCompleted: 0 },
  });
}

export default function (data) {
  const token = data.tokens[Math.floor(Math.random() * data.tokens.length)];
  const auth = { Authorization: `Bearer ${token}` };
  const stage = __ENV.STAGE;
  const pick = Math.random();

  if (pick < 0.7) {
    const period = Math.random() < 0.6 ? "all" : "week";
    const generation = Math.random() < 0.5 ? 0 : int(1, 5);
    const res = http.get(`${BASE_URL}/v1/leaderboard?period=${period}&generation=${generation}`, {
      headers: auth,
      tags: { route: "leaderboard", stage },
    });
    check(res, { "leaderboard 200": (r) => r.status === 200 });
  } else if (pick < 0.9) {
    const res = http.post(`${BASE_URL}/v1/sessions`, sessionBody(), {
      headers: { ...auth, "content-type": "application/json" },
      tags: { route: "sessions", stage },
    });
    if (res.status === 429) rateLimited.add(1);
    const ok = check(res, { "session 200": (r) => r.status === 200 });
    if (ok && res.json("flagged")) flaggedSessions.add(1);
  } else {
    const res = http.get(`${BASE_URL}/v1/packs`, { tags: { route: "packs", stage } });
    check(res, { "packs 200": (r) => r.status === 200 });
  }
}
