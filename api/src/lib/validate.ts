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
  return parseJsonText(await c.req.text());
}

/** Like readJson, but an empty body reads as `{}` (for endpoints whose every field is optional). */
export async function readOptionalJson(c: Context): Promise<unknown> {
  const text = await c.req.text();
  return text.trim() === "" ? {} : parseJsonText(text);
}

/** Parse JSON text; malformed JSON is a 400. */
export function parseJsonText(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
  }
}

/** A positive integer id, from a path or query string. */
export const idSchema = z.coerce.number().int().positive();
const id = idSchema;

/** A positive integer path parameter. */
export function idParam(c: Context, name = "id"): number {
  return parse(id, c.req.param(name), name);
}
