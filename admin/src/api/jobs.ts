import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { isActive } from "../lib/jobs";
import { apiFetch } from "./client";

export const jobSchema = z.object({
  id: z.number(),
  kind: z.enum(["scrape", "cut", "recut"]),
  status: z.enum(["queued", "running", "succeeded", "failed"]),
  params: z.unknown(),
  ghRunUrl: z.string().nullable(),
  startedAt: z.number().nullable(),
  finishedAt: z.number().nullable(),
  summary: z.unknown(),
});
export type JobRow = z.infer<typeof jobSchema>;

/** The 50 latest jobs, refreshed every 10 s while any of them is queued or running. */
export const useJobs = () =>
  useQuery({
    queryKey: ["jobs"],
    queryFn: async () => (await apiFetch("/admin/jobs", z.object({ jobs: z.array(jobSchema) }))).jobs,
    refetchInterval: (q) => (q.state.data?.some((j) => isActive(j.status)) ? 10_000 : false),
  });

export type JobStart = { kind: "scrape"; params: { limit?: number; since?: string } } | { kind: "cut"; params: { allMissing: true } };

export function useStartJob() {
  const qc = useQueryClient();
  return useMutation({
    meta: { silent: true },
    mutationFn: (req: JobStart) => apiFetch("/admin/jobs", z.object({ job: jobSchema }), { method: "POST", json: req }),
    // A refused dispatch (502) still leaves a failed job row: show it.
    onSettled: () => void qc.invalidateQueries({ queryKey: ["jobs"] }),
  });
}

/** One job, refreshed every 5 s until it has succeeded or failed (the clip editor follows its recut with this). */
export function useJobPoll(jobId: number | null) {
  return useQuery({
    queryKey: ["job", jobId],
    enabled: jobId !== null,
    queryFn: async () => (await apiFetch(`/admin/jobs?id=${jobId}`, z.object({ jobs: z.array(jobSchema) }))).jobs[0]!,
    refetchInterval: (q) => (q.state.data && !isActive(q.state.data.status) ? false : 5_000),
  });
}
