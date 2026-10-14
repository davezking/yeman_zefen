import { env } from "cloudflare:workers";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { clips, ingestJobs } from "../src/db/schema";
import { DispatchError, dispatchWorkflow } from "../src/lib/github";
import { planDispatch, type JobRequest } from "../src/lib/jobs";
import { githubAnswers, githubCalls } from "./githubFake";
import {
  api, installTestJwks, makeArtist, makeClip, makeJob, makeTrack, rawRequest, removeTestJwks, resetCatalog, seedAdmins, signAccessJwt, svc,
} from "./helpers";

beforeAll(async () => {
  await installTestJwks();
  await seedAdmins();
});
beforeEach(resetCatalog);
afterAll(() => removeTestJwks());

const json = async (res: Response) => (await res.json()) as any; // test-only: shapes are asserted below
const jobRows = () => db(env).select().from(ingestJobs).orderBy(ingestJobs.id);
const TOKEN = "test-gh-token";
const DISPATCH_URL = (file: string) => `https://api.github.com/repos/davezking/yeman_zefen/actions/workflows/${file}/dispatches`;

// ------------------------------------------------------------ POST /admin/jobs

describe("POST /admin/jobs", () => {
  it("queues a scrape job and dispatches ingest-scrape.yml with its inputs", async () => {
    const res = await api("/admin/jobs", { body: { kind: "scrape", params: { limit: 3, since: "2026-01-31" } } });
    expect(res.status).toBe(201);
    const { job } = await json(res);
    expect(job).toMatchObject({ kind: "scrape", status: "queued", params: { limit: 3, since: "2026-01-31" }, ghRunUrl: null, summary: null });

    expect(githubCalls).toHaveLength(1);
    const call = githubCalls[0]!;
    expect(call.method).toBe("POST");
    expect(call.url).toBe(DISPATCH_URL("ingest-scrape.yml"));
    expect(call.body).toEqual({ ref: "main", inputs: { job_id: String(job.id), limit: "3", since: "2026-01-31" } });
    expect(call.headers).toMatchObject({
      authorization: `Bearer ${TOKEN}`,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "yeman-zefen-api",
    });
    const [row] = await jobRows();
    expect(row).toMatchObject({ id: job.id, kind: "scrape", status: "queued", paramsJson: '{"limit":3,"since":"2026-01-31"}' });
  });

  it("a scrape needs no params", async () => {
    const res = await api("/admin/jobs", { body: { kind: "scrape" } });
    expect(res.status).toBe(201);
    expect(githubCalls[0]!.body.inputs).toEqual({ job_id: String((await json(res)).job.id) });
  });

  it.each<[string, Record<string, unknown>, string]>([
    ["named tracks", { trackIds: [3, 1, 2] }, "--track-ids 3,1,2"],
    ["named tracks, one clip type", { trackIds: [7], type: "intro" }, "--track-ids 7 --type intro"],
    ["everything missing", { allMissing: true }, "--all-missing"],
    ["everything missing, limited, one type", { allMissing: true, limit: 25, type: "middle" }, "--all-missing --limit 25 --type middle"],
  ])("queues a cut job for %s", async (_name, params, args) => {
    const res = await api("/admin/jobs", { body: { kind: "cut", params } });
    expect(res.status).toBe(201);
    const { job } = await json(res);
    expect(githubCalls[0]!.url).toBe(DISPATCH_URL("ingest-cut.yml"));
    expect(githubCalls[0]!.body.inputs).toEqual({ job_id: String(job.id), args });
  });

  it("queues a recut job for one clip, with its start", async () => {
    const res = await api("/admin/jobs", { body: { kind: "recut", params: { trackId: 7, type: "intro", startMs: 41_200 } } });
    expect(res.status).toBe(201);
    const { job } = await json(res);
    expect(job).toMatchObject({ kind: "recut", status: "queued" });
    expect(githubCalls[0]!.url).toBe(DISPATCH_URL("ingest-cut.yml"));
    expect(githubCalls[0]!.body.inputs).toEqual({ job_id: String(job.id), args: "--track-id 7 --type intro --start-ms 41200" });
  });

  it.each<[string, unknown]>([
    ["an unknown kind", { kind: "reindex", params: {} }],
    ["no kind", { params: {} }],
    ["scrape: limit 0", { kind: "scrape", params: { limit: 0 } }],
    ["scrape: fractional limit", { kind: "scrape", params: { limit: 1.5 } }],
    ["scrape: a date that does not exist", { kind: "scrape", params: { since: "2026-02-30" } }],
    ["scrape: a date in the wrong format", { kind: "scrape", params: { since: "13/10/2026" } }],
    ["scrape: an unknown param", { kind: "scrape", params: { force: true } }],
    ["cut: no selection", { kind: "cut", params: {} }],
    ["cut: both selections", { kind: "cut", params: { trackIds: [1], allMissing: true } }],
    ["cut: allMissing false", { kind: "cut", params: { allMissing: false } }],
    ["cut: limit without allMissing", { kind: "cut", params: { trackIds: [1], limit: 5 } }],
    ["cut: no tracks", { kind: "cut", params: { trackIds: [] } }],
    ["cut: too many tracks", { kind: "cut", params: { trackIds: Array.from({ length: 201 }, (_, i) => i + 1) } }],
    ["cut: a track id that is not a positive integer", { kind: "cut", params: { trackIds: [0] } }],
    ["cut: a clip type that does not exist", { kind: "cut", params: { allMissing: true, type: "outro" } }],
    ["cut: arguments passed straight through", { kind: "cut", params: { allMissing: true, args: "--evil" } }],
    ["cut: no params at all", { kind: "cut" }],
    ["recut: no start", { kind: "recut", params: { trackId: 1, type: "intro" } }],
    ["recut: negative start", { kind: "recut", params: { trackId: 1, type: "intro", startMs: -1 } }],
    ["recut: no clip type", { kind: "recut", params: { trackId: 1, startMs: 0 } }],
    ["an unknown top-level field", { kind: "scrape", params: {}, extra: 1 }],
  ])("rejects %s before creating anything or calling GitHub", async (_name, body) => {
    const res = await api("/admin/jobs", { body });
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("validation_error");
    expect(await jobRows()).toHaveLength(0);
    expect(githubCalls).toHaveLength(0);
  });

  it("rejects a body that is not JSON", async () => {
    const jwt = await signAccessJwt({ email: "admin@yz.test" });
    const res = await rawRequest("/admin/jobs", { method: "POST", jwt, headers: { "content-type": "application/json" }, body: "{nope" });
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("invalid_json");
  });

  describe("when GitHub will not start the workflow", () => {
    const failedJob = async () => {
      const [row] = await jobRows();
      return { row: row!, summary: JSON.parse(row!.summaryJson ?? "null") };
    };

    it("keeps the job as failed, with GitHub's reason, and answers 502", async () => {
      githubAnswers(() => new Response(JSON.stringify({ message: "Not Found", documentation_url: "https://docs.github.com" }), { status: 404 }));
      const res = await api("/admin/jobs", { body: { kind: "scrape", params: {} } });
      expect(res.status).toBe(502);
      const { error } = await json(res);
      const { row, summary } = await failedJob();
      expect(error.code).toBe("dispatch_failed");
      expect(error.message).toContain(`Job ${row.id}`);
      expect(error.message).toContain("GitHub returned 404: Not Found");
      expect(row.status).toBe("failed");
      expect(row.finishedAt).toBeTypeOf("number");
      expect(summary).toEqual({ error: "GitHub returned 404: Not Found" });
    });

    it("says so when the token lacks permission", async () => {
      githubAnswers(() => new Response(JSON.stringify({ message: "Resource not accessible by personal access token" }), { status: 403 }));
      await api("/admin/jobs", { body: { kind: "scrape", params: {} } });
      expect((await failedJob()).summary.error).toBe("GitHub returned 403: Resource not accessible by personal access token");
    });

    it("copes with an answer that is not JSON", async () => {
      githubAnswers(() => new Response("<html>Bad gateway</html>", { status: 502 }));
      const res = await api("/admin/jobs", { body: { kind: "scrape", params: {} } });
      expect(res.status).toBe(502);
      expect((await failedJob()).summary.error).toBe("GitHub returned 502");
    });

    it("copes with GitHub being unreachable, and never repeats the thrown error's text", async () => {
      githubAnswers(() => {
        throw new TypeError(`connect failed with Authorization: Bearer ${TOKEN}`);
      });
      const res = await api("/admin/jobs", { body: { kind: "scrape", params: {} } });
      expect(res.status).toBe(502);
      const { row, summary } = await failedJob();
      expect(summary.error).toBe("Could not reach GitHub");
      expect(JSON.stringify([await json(res), row])).not.toContain(TOKEN);
    });

    it("lists the failed job", async () => {
      githubAnswers(() => new Response(null, { status: 500 }));
      await api("/admin/jobs", { body: { kind: "scrape", params: {} } });
      const list = await json(await api("/admin/jobs"));
      expect(list.jobs).toHaveLength(1);
      expect(list.jobs[0]).toMatchObject({ kind: "scrape", status: "failed", summary: { error: "GitHub returned 500" } });
    });
  });

  it("is open to admins and editors, and to nobody else", async () => {
    const body = { kind: "scrape", params: {} };
    expect((await api("/admin/jobs", { as: "editor", body })).status).toBe(201);
    expect((await rawRequest("/admin/jobs", { method: "POST", body: JSON.stringify(body) })).status).toBe(401);
    const service = await signAccessJwt({ common_name: "test-service.client" });
    const asService = await rawRequest("/admin/jobs", { method: "POST", jwt: service, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    expect(asService.status).toBe(403); // the ingest token cannot start jobs
    const stranger = await signAccessJwt({ email: "nobody@yz.test" });
    expect((await rawRequest("/admin/jobs", { method: "POST", jwt: stranger, headers: { "content-type": "application/json" }, body: JSON.stringify(body) })).status).toBe(403);
    expect(githubCalls).toHaveLength(1);
  });
});

// ------------------------------------------------------------- GET /admin/jobs

describe("GET /admin/jobs", () => {
  it("lists the newest 50, newest first, with params and summary as objects", async () => {
    for (let i = 0; i < 55; i++) await makeJob("scrape", "succeeded");
    const newest = await makeJob("cut", "running");
    await db(env).update(ingestJobs).set({ paramsJson: '{"allMissing":true}', summaryJson: '{"created":4}', ghRunUrl: "https://github.com/o/r/actions/runs/9", startedAt: 5 }).where(eq(ingestJobs.id, newest.id));

    const res = await api("/admin/jobs", { as: "editor" });
    expect(res.status).toBe(200);
    const { jobs } = await json(res);
    expect(jobs).toHaveLength(50);
    expect(jobs[0]).toEqual({ id: newest.id, kind: "cut", status: "running", params: { allMissing: true }, ghRunUrl: "https://github.com/o/r/actions/runs/9", startedAt: 5, finishedAt: null, summary: { created: 4 } });
    expect(jobs.map((j: any) => j.id)).toEqual([...jobs.map((j: any) => j.id)].sort((a: number, b: number) => b - a));
  });

  it("returns null for a JSON column that does not parse rather than failing", async () => {
    const job = await makeJob("scrape");
    await db(env).update(ingestJobs).set({ summaryJson: "{broken" }).where(eq(ingestJobs.id, job.id));
    expect((await json(await api("/admin/jobs"))).jobs[0]).toMatchObject({ id: job.id, params: null, summary: null });
  });

  it("is for signed-in admins only", async () => {
    expect((await rawRequest("/admin/jobs")).status).toBe(401);
    const service = await signAccessJwt({ common_name: "test-service.client" });
    expect((await rawRequest("/admin/jobs", { jwt: service })).status).toBe(403);
  });
});

// ------------------------------------------------ POST /admin/ingest/jobs (service)

describe("POST /admin/ingest/jobs", () => {
  it("creates a queued job for a run that is already underway, and dispatches nothing", async () => {
    const res = await svc("/admin/ingest/jobs", { body: { kind: "scrape", params: { since: "2026-09-13" } } });
    expect(res.status).toBe(201);
    const { jobId } = await json(res);
    expect(jobId).toBeTypeOf("number");
    const [row] = await jobRows();
    expect(row).toMatchObject({ id: jobId, kind: "scrape", status: "queued", paramsJson: '{"since":"2026-09-13"}' });
    expect(githubCalls).toHaveLength(0);
  });

  it("takes the same requests as POST /admin/jobs, and rejects the same bad ones", async () => {
    expect((await svc("/admin/ingest/jobs", { body: { kind: "scrape" } })).status).toBe(201);
    expect((await svc("/admin/ingest/jobs", { body: { kind: "cut", params: { allMissing: true } } })).status).toBe(201);
    expect((await svc("/admin/ingest/jobs", { body: { kind: "scrape", params: { since: "soon" } } })).status).toBe(400);
    expect((await svc("/admin/ingest/jobs", { body: { kind: "cut", params: {} } })).status).toBe(400);
    expect(await jobRows()).toHaveLength(2);
  });

  it("the job it creates can be moved on with the status route", async () => {
    const { jobId } = await json(await svc("/admin/ingest/jobs", { body: { kind: "scrape" } }));
    const run = await svc(`/admin/ingest/jobs/${jobId}/status`, { body: { status: "running", ghRunUrl: "https://github.com/o/r/actions/runs/1" } });
    expect(run.status).toBe(200);
    const done = await svc(`/admin/ingest/jobs/${jobId}/status`, { body: { status: "succeeded", summary: { scraped: 3 } } });
    expect((await json(done)).job).toMatchObject({ status: "succeeded" });
  });

  it("is for the service token only", async () => {
    const human = await signAccessJwt({ email: "admin@yz.test" });
    const res = await rawRequest("/admin/ingest/jobs", { method: "POST", jwt: human, headers: { "content-type": "application/json" }, body: JSON.stringify({ kind: "scrape" }) });
    expect(res.status).toBe(403);
    expect((await rawRequest("/admin/ingest/jobs", { method: "POST" })).status).toBe(401);
  });
});

// ------------------------------------------- the clip editor asks for a recut

describe("PATCH /admin/clips/:id starts a recut", () => {
  const setup = async () => {
    const track = await makeTrack((await makeArtist("አርቲስት")).id, { durationMs: 200_000 });
    return { track, clip: await makeClip(track.id, "middle") };
  };

  it("queues a recut job for that clip and dispatches ingest-cut.yml", async () => {
    const { track, clip } = await setup();
    const res = await api(`/admin/clips/${clip.id}`, { method: "PATCH", body: { start_ms: 42_000 } });
    expect(res.status).toBe(200);
    const body = await json(res);
    expect(body).toMatchObject({ needsRecut: true, clip: { id: clip.id, startMs: 42_000, status: "pending" } });
    expect(body.job).toMatchObject({ kind: "recut", status: "queued", params: { trackId: track.id, type: "middle", startMs: 42_000 } });
    expect(githubCalls).toHaveLength(1);
    expect(githubCalls[0]!.url).toBe(DISPATCH_URL("ingest-cut.yml"));
    expect(githubCalls[0]!.body.inputs).toEqual({ job_id: String(body.job.id), args: `--track-id ${track.id} --type middle --start-ms 42000` });
  });

  it("saves the edit even when GitHub refuses, and records the failed job", async () => {
    const { clip } = await setup();
    githubAnswers(() => new Response(JSON.stringify({ message: "Bad credentials" }), { status: 401 }));
    const res = await api(`/admin/clips/${clip.id}`, { method: "PATCH", body: { start_ms: 42_000 } });
    expect(res.status).toBe(200); // the start was saved
    const body = await json(res);
    expect(body.clip).toMatchObject({ startMs: 42_000, status: "pending" }); // and the clip waits for the next cut
    expect(body.job).toMatchObject({ kind: "recut", status: "failed", summary: { error: "GitHub returned 401: Bad credentials" } });
    expect((await db(env).select().from(clips).where(eq(clips.id, clip.id)))[0]).toMatchObject({ startMs: 42_000, status: "pending" });
  });

  it("starts no job when the edit is rejected", async () => {
    const { clip } = await setup();
    expect((await api(`/admin/clips/${clip.id}`, { method: "PATCH", body: { start_ms: 999_999 } })).status).toBe(400);
    expect(await jobRows()).toHaveLength(0);
    expect(githubCalls).toHaveLength(0);
  });
});

// ----------------------------------------------------------------- the pieces

describe("planDispatch", () => {
  const plan = (req: JobRequest, id = 12) => planDispatch(req, id);

  it("sends only the inputs that were given", () => {
    expect(plan({ kind: "scrape", params: {} })).toEqual({ workflow: "ingest-scrape.yml", inputs: { job_id: "12" } });
    expect(plan({ kind: "scrape", params: { limit: 5 } }).inputs).toEqual({ job_id: "12", limit: "5" });
  });

  it("builds cut arguments from validated values only", () => {
    expect(plan({ kind: "cut", params: { trackIds: [1, 2], type: "intro" } }).inputs.args).toBe("--track-ids 1,2 --type intro");
    expect(plan({ kind: "cut", params: { allMissing: true, limit: 9 } }).inputs.args).toBe("--all-missing --limit 9");
  });

  it("uses the same workflow for cut and recut, and the job id as a string", () => {
    const cut = plan({ kind: "cut", params: { allMissing: true } });
    const recut = plan({ kind: "recut", params: { trackId: 3, type: "intro", startMs: 0 } });
    expect(cut.workflow).toBe(recut.workflow);
    expect(recut.inputs).toEqual({ job_id: "12", args: "--track-id 3 --type intro --start-ms 0" });
  });
});

describe("dispatchWorkflow", () => {
  const config = { ...env, GH_DISPATCH_TOKEN: TOKEN, GH_REPO: "o/r", GH_REF: "main" };

  it("resolves on 204 and sends the ref and inputs", async () => {
    await dispatchWorkflow(config, "ingest-cut.yml", { job_id: "1", args: "--all-missing" });
    expect(githubCalls[0]!.url).toBe("https://api.github.com/repos/o/r/actions/workflows/ingest-cut.yml/dispatches");
    expect(githubCalls[0]!.body).toEqual({ ref: "main", inputs: { job_id: "1", args: "--all-missing" } });
  });

  it.each([
    ["no token", { ...config, GH_DISPATCH_TOKEN: undefined }, /not configured/],
    ["an empty token", { ...config, GH_DISPATCH_TOKEN: "" }, /not configured/],
    ["no repo", { ...config, GH_REPO: "" }, /not configured/],
    ["no ref", { ...config, GH_REF: "" }, /not configured/],
    ["a repo that is not owner/name", { ...config, GH_REPO: "o/r/../../evil" }, /owner\/name/],
    ["a repo with a query string", { ...config, GH_REPO: "o/r?x=1" }, /owner\/name/],
  ])("refuses with %s, without calling GitHub", async (_name, cfg, message) => {
    await expect(dispatchWorkflow(cfg, "ingest-cut.yml", {})).rejects.toThrow(message);
    await expect(dispatchWorkflow(cfg, "ingest-cut.yml", {})).rejects.toBeInstanceOf(DispatchError);
    expect(githubCalls).toHaveLength(0);
  });

  it("trims a long error message from GitHub", async () => {
    githubAnswers(() => new Response(JSON.stringify({ message: "x".repeat(1_000) }), { status: 422 }));
    await expect(dispatchWorkflow(config, "ingest-cut.yml", {})).rejects.toThrow(`GitHub returned 422: ${"x".repeat(300)}`);
    const err = await dispatchWorkflow(config, "ingest-cut.yml", {}).catch((e: Error) => e);
    expect((err as Error).message.length).toBeLessThan(330);
  });

  it("reports a timeout as one", async () => {
    githubAnswers(() => {
      throw new DOMException("The operation timed out", "TimeoutError");
    });
    await expect(dispatchWorkflow(config, "ingest-cut.yml", {})).rejects.toThrow(/did not answer within 10 s/);
  });

  it("encodes the workflow file name into the path", async () => {
    await dispatchWorkflow(config, "a/b c.yml", {});
    expect(githubCalls[0]!.url).toBe("https://api.github.com/repos/o/r/actions/workflows/a%2Fb%20c.yml/dispatches");
  });
});
