import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { AppEnv } from "../env";

/** Throw from any handler to return `{ error: { code, message } }` with the given status. */
export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function errorBody(code: string, message: string) {
  return { error: { code, message } };
}

export function onError(err: Error, c: Context<AppEnv>) {
  if (err instanceof ApiError) {
    c.set("errorCode", err.code);
    return c.json(errorBody(err.code, err.message), err.status);
  }
  if (err instanceof HTTPException) {
    c.set("errorCode", "http_error");
    return c.json(errorBody("http_error", err.message || "Request failed"), err.status);
  }
  c.set("errorCode", "internal");
  console.error(JSON.stringify({ requestId: c.get("requestId"), error: String(err?.stack ?? err) }));
  return c.json(errorBody("internal", "Internal server error"), 500);
}

export function onNotFound(c: Context<AppEnv>) {
  c.set("errorCode", "not_found");
  return c.json(errorBody("not_found", "Route not found"), 404);
}
