// The signed-in player's own profile. Mounted at /v1/me behind requireUser.
import { eq, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db } from "../db/client";
import { gameSessions, leaderboardEntries, users } from "../db/schema";
import type { AppEnv } from "../env";
import { displayNameSchema } from "../lib/displayName";
import { ApiError } from "../lib/errors";
import { DELETED_USER_ID } from "../lib/firebaseAuth";
import { parse, readOptionalJson } from "../lib/validate";

export const me = new Hono<AppEnv>();

const putBody = z.object({ displayName: displayNameSchema.optional() }).strict();

type UserRow = typeof users.$inferSelect;

function profile(row: UserRow) {
  return {
    id: row.id,
    displayName: row.displayName,
    isAnonymous: row.isAnonymous,
    country: row.country,
    createdAt: row.createdAt,
    lastSeenAt: row.lastSeenAt,
  };
}

// Create or update the caller. The token decides identity and anonymity; the client only
// supplies the display name. Country comes from Cloudflare, never from the client.
me.put("/", async (c) => {
  const user = c.get("user")!;
  const body = parse(putBody, await readOptionalJson(c));
  const cf = c.req.raw.cf as { country?: string } | undefined;
  const country = typeof cf?.country === "string" && /^[A-Z]{2}$/.test(cf.country) ? cf.country : null;
  const now = Date.now();
  // One statement. An omitted name or an unknown country keeps what is stored.
  const [row] = await db(c.env)
    .insert(users)
    .values({
      id: user.uid,
      displayName: body.displayName ?? null,
      isAnonymous: user.isAnonymous,
      country,
      createdAt: now,
      lastSeenAt: now,
    })
    .onConflictDoUpdate({
      target: users.id,
      set: {
        isAnonymous: user.isAnonymous,
        lastSeenAt: now,
        displayName: sql`COALESCE(excluded.display_name, ${users.displayName})`,
        country: sql`COALESCE(excluded.country, ${users.country})`,
      },
    })
    .returning();
  return c.json(profile(row!));
});

me.get("/", async (c) => {
  const user = c.get("user")!;
  const row = await db(c.env).select().from(users).where(eq(users.id, user.uid)).get();
  if (!row) throw new ApiError(404, "not_found", "No profile yet");
  return c.json(profile(row));
});

// Account deletion (required by both stores). One batch, so it is all or nothing: leaderboard
// presence goes, past sessions stay under the placeholder user (royalty counts depend on them),
// and the user row goes. Deleting an account that is already gone succeeds.
me.delete("/", async (c) => {
  const user = c.get("user")!;
  const d = db(c.env);
  await d.batch([
    d.delete(leaderboardEntries).where(eq(leaderboardEntries.userId, user.uid)),
    d.update(gameSessions).set({ userId: DELETED_USER_ID }).where(eq(gameSessions.userId, user.uid)),
    d.delete(users).where(eq(users.id, user.uid)),
  ]);
  return c.body(null, 204);
});
