// Typed fetch wrapper for the Worker. Every request carries the Access cookie
// (`credentials: 'include'`). Failures are thrown as ApiError, built from the
// Worker's `{ error: { code, message } }` body, and shown by the query client's
// global error handler (see src/queryClient.ts).
import { z } from "zod";

export const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8787";

const errorBodySchema = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function apiFetch<T>(
  path: string,
  schema: z.ZodType<T>,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body !== undefined && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, { ...init, headers, credentials: "include" });
  } catch {
    throw new ApiError(0, "network", "Cannot reach the API. Check your connection and try again.");
  }

  const body: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const parsed = errorBodySchema.safeParse(body);
    if (parsed.success) {
      throw new ApiError(res.status, parsed.data.error.code, parsed.data.error.message);
    }
    throw new ApiError(res.status, "http_error", `Request failed with status ${res.status}`);
  }

  const data = schema.safeParse(body);
  if (!data.success) {
    throw new ApiError(res.status, "bad_response", "The API returned an unexpected response.");
  }
  return data.data;
}
