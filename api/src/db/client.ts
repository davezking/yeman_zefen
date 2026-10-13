import { drizzle } from "drizzle-orm/d1";
import type { Bindings } from "../env";
import * as schema from "./schema";

/** Typed Drizzle client over the `DB` D1 binding. */
export function db(env: Pick<Bindings, "DB">) {
  return drizzle(env.DB, { schema });
}

export type Db = ReturnType<typeof db>;
export { schema };
