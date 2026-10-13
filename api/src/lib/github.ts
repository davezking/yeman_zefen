// Dispatches the ingest workflows through GitHub's REST API.
// https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event
//
// The Worker holds a fine-grained PAT (secret GH_DISPATCH_TOKEN) with Actions read/write on one
// repository and nothing else. The token only ever goes in the Authorization header: no error message,
// log line or job row below includes it.
import type { Bindings } from "../env";

/** A dispatch that did not happen. The message is safe to store and to show to an admin. */
export class DispatchError extends Error {}

const REPO_PATTERN = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const TIMEOUT_MS = 10_000;

// Test-only seam, like accessAuth's: lets tests stand in for GitHub. Never set in production code.
let testFetch: typeof fetch | null = null;

/** Test-only. Pass a fake `fetch`, or null to restore the real one. */
export function __setGithubFetch(fn: typeof fetch | null): void {
  testFetch = fn;
}

/**
 * Start `workflow` (a file name such as `ingest-cut.yml`) on GH_REF with the given inputs.
 * Resolves on GitHub's 204; throws DispatchError otherwise.
 */
export async function dispatchWorkflow(env: Bindings, workflow: string, inputs: Record<string, string>): Promise<void> {
  const token = env.GH_DISPATCH_TOKEN;
  if (!token || !env.GH_REPO || !env.GH_REF) {
    throw new DispatchError("GitHub dispatch is not configured (GH_DISPATCH_TOKEN, GH_REPO and GH_REF are all required)");
  }
  if (!REPO_PATTERN.test(env.GH_REPO)) throw new DispatchError("GH_REPO must look like owner/name");

  const url = `https://api.github.com/repos/${env.GH_REPO}/actions/workflows/${encodeURIComponent(workflow)}/dispatches`;
  let res: Response;
  try {
    res = await (testFetch ?? fetch)(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "yeman-zefen-api", // GitHub rejects requests without one
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ref: env.GH_REF, inputs }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "TimeoutError";
    throw new DispatchError(timedOut ? `GitHub did not answer within ${TIMEOUT_MS / 1000} s` : "Could not reach GitHub");
  }
  if (res.status === 204) return;

  let detail = "";
  try {
    detail = String(((await res.json()) as { message?: unknown }).message ?? "").slice(0, 300);
  } catch {
    // not JSON: the status alone will do
  }
  throw new DispatchError(`GitHub returned ${res.status}${detail ? `: ${detail}` : ""}`);
}
