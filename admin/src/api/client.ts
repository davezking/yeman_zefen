// Typed fetch wrapper for the Worker. Every request carries the admin's sign-in: the Access cookie
// (`credentials: 'include'`), or with VITE_ADMIN_LOGIN=firebase the Firebase ID token as a Bearer token
// (see src/auth/login.ts). Failures are thrown as ApiError, built from the Worker's
// `{ error: { code, message } }` body, and shown by the query client's global error handler
// (see src/queryClient.ts).
import { z } from "zod";
import { adminLogin } from "../auth/login";

// Production builds fail without VITE_API_BASE (vite.config.ts), so the fallback only applies in dev.
export const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8787";

/** Schema for endpoints that answer 204 No Content. */
export const noContent = z.undefined();

const errorBodySchema = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    /** The Worker's X-Request-Id, for finding the request in the Worker logs. */
    readonly requestId?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export type ApiRequestInit = RequestInit & {
  /** Sent as a JSON body with `Content-Type: application/json`. Use `body` for anything else (FormData, Blob). */
  json?: unknown;
};

export async function apiFetch<T>(path: string, schema: z.ZodType<T>, init: ApiRequestInit = {}): Promise<T> {
  const { json, ...rest } = init;
  const headers = new Headers(rest.headers);
  let body = rest.body;
  if (json !== undefined) {
    headers.set("content-type", "application/json");
    body = JSON.stringify(json);
  }

  const res = await send(path, { ...rest, headers, body });

  const requestId = res.headers.get("x-request-id") ?? undefined;
  const text = await res.text().catch(() => "");
  let parsedBody: unknown = undefined;
  let jsonOk = true;
  if (text !== "") {
    try {
      parsedBody = JSON.parse(text);
    } catch {
      jsonOk = false;
    }
  }

  if (!res.ok) throw failure(res.status, parsedBody, requestId);

  const data = jsonOk ? schema.safeParse(parsedBody) : null;
  if (!data?.success) {
    throw new ApiError(res.status, "bad_response", "The API returned an unexpected response.", requestId);
  }
  return data.data;
}

/** fetch with the admin's sign-in. An unreachable API becomes an ApiError. */
async function send(path: string, init: RequestInit): Promise<Response> {
  const firebase = adminLogin() === "firebase";
  const headers = new Headers(init.headers);
  if (firebase) {
    const token = await (await import("../auth/firebase")).idToken();
    if (!token) throw new ApiError(401, "signed_out", "You are signed out. Sign in again.");
    headers.set("authorization", `Bearer ${token}`);
  }
  try {
    // No cookie is needed with a Bearer token, so none is sent.
    return await fetch(`${API_BASE}${path}`, { ...init, headers, credentials: firebase ? "omit" : "include" });
  } catch {
    // Behind Cloudflare Access an expired session also lands here: the redirect to the login page fails CORS.
    throw new ApiError(
      0,
      "network",
      firebase ? "Can't reach the API. Check your connection and try again." : "Can't reach the API. If your sign-in has expired, reload the page to sign in again.",
    );
  }
}

/** The ApiError for a non-2xx answer: the Worker's `{ error }` body when it sent one, else the status. */
function failure(status: number, body: unknown, requestId: string | undefined): ApiError {
  const err = errorBodySchema.safeParse(body);
  if (err.success) return new ApiError(status, err.data.error.code, err.data.error.message, requestId);
  return new ApiError(status, "http_error", `Request failed with status ${status}`, requestId);
}

/**
 * A file from the Worker (a CSV report), as a Blob. Like apiFetch it sends the Access cookie and
 * throws ApiError, so a refused request shows the Worker's message rather than a broken download.
 */
export async function apiFetchBlob(path: string, init: RequestInit = {}): Promise<Blob> {
  const res = await send(path, init);
  const requestId = res.headers.get("x-request-id") ?? undefined;
  if (!res.ok) {
    let body: unknown;
    try {
      body = JSON.parse(await res.text());
    } catch {
      body = undefined;
    }
    throw failure(res.status, body, requestId);
  }
  return res.blob();
}
