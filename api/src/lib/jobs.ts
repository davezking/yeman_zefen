// Ingest jobs: what an admin (or the clip editor) can ask for, the workflow inputs that follow from it, and
// the create-then-dispatch step that gives every request a row in `ingest_jobs`.
//
// Workflow arguments are built here from validated numbers and enums only. Nothing free-form from a request
// reaches a workflow's command line.
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "../db/client";
import { CLIP_TYPES, ingestJobs } from "../db/schema";
import type { Bindings } from "../env";
import { DispatchError, dispatchWorkflow } from "./github";

export type JobRow = typeof ingestJobs.$inferSelect;

const trackId = z.number().int().positive();
const clipType = z.enum(CLIP_TYPES);

export const scrapeParams = z.strictObject({
  limit: z.number().int().min(1).max(10_000).optional(),
  since: z.iso.date().optional(),
});

export const cutParams = z
  .strictObject({
    trackIds: z.array(trackId).min(1).max(200).optional(),
    allMissing: z.literal(true).optional(),
    type: clipType.optional(),
    limit: z.number().int().min(1).max(1_000).optional(),
  })
  .refine((p) => (p.trackIds !== undefined) !== (p.allMissing !== undefined), "send exactly one of trackIds or allMissing")
  .refine((p) => p.limit === undefined || p.allMissing === true, "limit goes with allMissing");

export const recutParams = z.strictObject({
  trackId,
  type: clipType,
  startMs: z.number().int().min(0),
});

export const jobRequest = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("scrape"), params: scrapeParams.default({}) }),
  z.strictObject({ kind: z.literal("cut"), params: cutParams }),
  z.strictObject({ kind: z.literal("recut"), params: recutParams }),
]);
export type JobRequest = z.infer<typeof jobRequest>;

export const SCRAPE_WORKFLOW = "ingest-scrape.yml";
export const CUT_WORKFLOW = "ingest-cut.yml";

/** The workflow to start and its inputs (GitHub wants strings), for a job that has an id. */
export function planDispatch(req: JobRequest, jobId: number): { workflow: string; inputs: Record<string, string> } {
  const job_id = String(jobId);
  switch (req.kind) {
    case "scrape": {
      const inputs: Record<string, string> = { job_id };
      if (req.params.limit !== undefined) inputs.limit = String(req.params.limit);
      if (req.params.since !== undefined) inputs.since = req.params.since;
      return { workflow: SCRAPE_WORKFLOW, inputs };
    }
    case "cut": {
      const p = req.params;
      const args = p.allMissing ? ["--all-missing", ...(p.limit !== undefined ? ["--limit", String(p.limit)] : [])] : ["--track-ids", p.trackIds!.join(",")];
      if (p.type) args.push("--type", p.type);
      return { workflow: CUT_WORKFLOW, inputs: { job_id, args: args.join(" ") } };
    }
    case "recut": {
      const p = req.params;
      return { workflow: CUT_WORKFLOW, inputs: { job_id, args: `--track-id ${p.trackId} --type ${p.type} --start-ms ${p.startMs}` } };
    }
  }
}

/** Insert a `queued` job row. Used directly for runs that are already underway (the scheduled scrape). */
export async function insertJob(env: Bindings, req: JobRequest): Promise<JobRow> {
  const [job] = await db(env)
    .insert(ingestJobs)
    .values({ kind: req.kind, status: "queued", paramsJson: JSON.stringify(req.params) })
    .returning();
  return job!;
}

/**
 * Create the job, then dispatch its workflow. A job always ends up with a row: if GitHub refuses (or is
 * unreachable, or the Worker is not configured) the row is marked `failed` with the reason, so nothing sits in
 * `queued` waiting for a run that will never start. `error` is set exactly when that happened.
 */
export async function createJob(env: Bindings, req: JobRequest): Promise<{ job: JobRow; error?: string }> {
  const job = await insertJob(env, req);
  const { workflow, inputs } = planDispatch(req, job.id);
  try {
    await dispatchWorkflow(env, workflow, inputs);
    return { job };
  } catch (err) {
    let message = "Unexpected error while dispatching the workflow";
    if (err instanceof DispatchError) message = err.message;
    else console.error("dispatch failed", err instanceof Error ? err.message : String(err));
    const [failed] = await db(env)
      .update(ingestJobs)
      .set({ status: "failed", finishedAt: Date.now(), summaryJson: JSON.stringify({ error: message }) })
      .where(eq(ingestJobs.id, job.id))
      .returning();
    return { job: failed!, error: message };
  }
}

function parseJson(text: string | null): unknown {
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** A job as the admin API returns it: the JSON columns as objects. */
export function jobOut(j: JobRow) {
  return {
    id: j.id,
    kind: j.kind,
    status: j.status,
    params: parseJson(j.paramsJson),
    ghRunUrl: j.ghRunUrl,
    startedAt: j.startedAt,
    finishedAt: j.finishedAt,
    summary: parseJson(j.summaryJson),
  };
}
