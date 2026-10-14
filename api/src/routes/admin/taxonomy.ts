// Read-only lookups the admin UI needs for its era and genre pickers and filters.
import { Hono } from "hono";
import { db } from "../../db/client";
import { generations, genres } from "../../db/schema";
import type { AppEnv } from "../../env";

export const taxonomy = new Hono<AppEnv>();

// Both tables are small seed data (a handful of rows), so they are returned whole, not paginated.
taxonomy.get("/generations", async (c) => {
  const items = await db(c.env).select().from(generations).orderBy(generations.sort);
  return c.json({ items });
});

taxonomy.get("/genres", async (c) => {
  const items = await db(c.env).select().from(genres).orderBy(genres.nameEn);
  return c.json({ items });
});
