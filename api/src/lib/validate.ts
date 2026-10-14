import type { Context } from "hono";
import { z } from "zod";
import { ApiError } from "./errors";

/** Parse `data` with `schema`, turning failures into a 400 `validation_error`. */
export function parse<T extends z.ZodType>(schema: T, data: unknown, label = "body"): z.infer<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const message = result.error.issues
      .map((i) => `${i.path.length ? i.path.join(".") : label}: ${i.message}`)
      .join("; ");
    throw new ApiError(400, "validation_error", message);
  }
  return result.data;
}

/** Read a JSON body; malformed JSON is a 400, not a 500. */
export async function readJson(c: Context): Promise<unknown> {
  try {
    return await c.req.json();
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
  }
}

/** Like readJson, but an empty body reads as `{}` (for endpoints whose every field is optional). */
export async function readOptionalJson(c: Context): Promise<unknown> {
  const text = await c.req.text();
  if (text.trim() === "") return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
  }
}

const id = z.coerce.number().int().positive();

/** A positive integer path parameter. */
export function idParam(c: Context, name = "id"): number {
  return parse(id, c.req.param(name), name);
}
