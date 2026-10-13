// Ingest jobs for admins: start one (which dispatches its GitHub workflow) and list recent ones.
// Spec: docs/architecture.md §5 "Jobs".
import { desc } from "drizzle-orm";
import { Hono } from "hono";
import { db } from "../../db/client";
import { ingestJobs } from "../../db/schema";
import type { AppEnv } from "../../env";
import { ApiError } from "../../lib/errors";
import { createJob, jobOut, jobRequest } from "../../lib/jobs";
import { parse, readJson } from "../../lib/validate";

export const jobRoutes = new Hono<AppEnv>();

const LIST_LIMIT = 50;

// POST /admin/jobs { kind, params }: 201 with the job once its workflow has been dispatched. If GitHub
// refuses, the job is kept (as `failed`, with the reason) and the request is a 502 that says so.
jobRoutes.post("/jobs", async (c) => {
  const req = parse(jobRequest, await readJson(c));
  const { job, error } = await createJob(c.env, req);
  if (error) {
    throw new ApiError(502, "dispatch_failed", `Job ${job.id} was recorded as failed because the workflow could not be started: ${error}`);
  }
  return c.json({ job: jobOut(job) }, 201);
});

jobRoutes.get("/jobs", async (c) => {
  const rows = await db(c.env).select().from(ingestJobs).orderBy(desc(ingestJobs.id)).limit(LIST_LIMIT);
  return c.json({ jobs: rows.map(jobOut) });
});
