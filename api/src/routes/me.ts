// The signed-in player's own profile, and turning a guest into a registered player.
// Mounted at /v1/me behind requireUser.
import { eq, sql } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db } from "../db/client";
import { gameSessions, leaderboardEntries, users } from "../db/schema";
import type { AppEnv } from "../env";
import { requestCountry } from "../lib/country";
import { displayNameSchema } from "../lib/displayName";
import { ApiError } from "../lib/errors";
import { backfillStatements } from "../lib/backfill";
import {
  DELETED_USER_ID,
  InvalidTokenError,
  KeysUnavailableError,
  requireUser,
  verifyFirebaseIdToken,
  type PlayerUser,
} from "../lib/firebaseAuth";
import { parse, readJson, readOptionalJson } from "../lib/validate";

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
  const country = requestCountry(c.req.raw);
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
        // Once registered, always registered: a guest token still cached on the device after linking
        // must not turn the account back into a guest.
        isAnonymous: sql`MIN(${users.isAnonymous}, excluded.is_anonymous)`,
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

// --- Registration and merging -------------------------------------------------------------

/** How old a guest's ID token may be for a merge. The app keeps it while offline and retries. */
export const MERGE_TOKEN_MAX_AGE_S = 30 * 86_400;

// Marks the caller registered (creating the row if needed) and returns it. ?1 uid, ?2 country, ?3 now.
const REGISTER_SQL = `
  INSERT INTO users (id, display_name, is_anonymous, country, created_at, last_seen_at)
  VALUES (?1, NULL, 0, ?2, ?3, ?3)
  ON CONFLICT (id) DO UPDATE SET
    is_anonymous = 0,
    last_seen_at = excluded.last_seen_at,
    country = COALESCE(excluded.country, users.country)
  RETURNING *`;

type RawUser = {
  id: string; display_name: string | null; is_anonymous: number; country: string | null;
  created_at: number; last_seen_at: number | null; shadow_banned: number; deleted_at: number | null;
};

function rawProfile(r: RawUser) {
  return {
    id: r.id,
    displayName: r.display_name,
    isAnonymous: r.is_anonymous === 1,
    country: r.country,
    createdAt: r.created_at,
    lastSeenAt: r.last_seen_at,
  };
}

/** Marks `uid` registered and rebuilds its leaderboard rows: 3 statements, one batch. Safe to repeat. */
async function registerAndBackfill(DB: D1Database, uid: string, country: string | null) {
  const [registered] = await DB.batch([DB.prepare(REGISTER_SQL).bind(uid, country, Date.now()), ...backfillStatements(DB, uid)]);
  return rawProfile((registered!.results as RawUser[])[0]!);
}

// After linking a provider to a guest (the uid is kept): flip the row to registered and rebuild
// the player's leaderboard rows from their sessions.
me.post("/registered", requireUser({ allowAnonymous: false }), async (c) => {
  return c.json(await registerAndBackfill(c.env.DB, c.get("user")!.uid, requestCountry(c.req.raw)));
});

const mergeBody = z.object({ anonymousIdToken: z.string().min(1).max(8192) }).strict();

// The guest uid's row only counts while it is still a guest; every write below re-checks that in
// the same transaction, so a guest that registers meanwhile is left alone. ?1 = guest uid.
const STILL_GUEST = "EXISTS (SELECT 1 FROM users WHERE id = ?1 AND is_anonymous = 1)";

// When a guest's credential already belongs to another account, the app signs into that account
// and sends the guest's ID token. The guest's sessions move to the caller, the guest row goes, and
// the caller's leaderboard rows are rebuilt. Replaying it moves nothing and changes nothing.
// A constant 8 statements: 1 read, then one batch of 7.
me.post("/merge", requireUser({ allowAnonymous: false }), async (c) => {
  const user = c.get("user")!;
  const { anonymousIdToken } = parse(mergeBody, await readJson(c));

  let guest: PlayerUser;
  try {
    guest = await verifyFirebaseIdToken(anonymousIdToken, c.env.FIREBASE_PROJECT_ID, {
      allowExpiredUpToS: MERGE_TOKEN_MAX_AGE_S,
    });
  } catch (err) {
    if (err instanceof KeysUnavailableError) {
      throw new ApiError(503, "auth_unavailable", "Authentication is temporarily unavailable");
    }
    const reason = err instanceof InvalidTokenError ? err.message : String(err);
    console.warn(JSON.stringify({ requestId: c.get("requestId"), event: "merge_token_rejected", reason }));
    throw new ApiError(401, "invalid_anonymous_token", "The guest token is invalid or too old");
  }
  // Two registered accounts are never merged: neither side can prove the other agreed to it.
  if (!guest.isAnonymous) {
    throw new ApiError(409, "not_a_guest", "Only a guest account can be merged into another account");
  }

  const DB = c.env.DB;
  const country = requestCountry(c.req.raw);
  // Linking kept the uid; there is nothing to move.
  if (guest.uid === user.uid) return c.json({ ...(await registerAndBackfill(DB, user.uid, country)), mergedSessions: 0 });

  const guestRow = await DB.prepare("SELECT is_anonymous FROM users WHERE id = ?1").bind(guest.uid).first<{ is_anonymous: number }>();
  // The guest uid has since registered (linked a provider of its own): its history is its own.
  if (guestRow && guestRow.is_anonymous === 0) {
    throw new ApiError(409, "already_registered", "That guest account has been registered and cannot be merged");
  }

  const results = await DB.batch([
    DB.prepare(REGISTER_SQL).bind(user.uid, country, Date.now()),
    // A shadow-banned guest stays banned in the account it joins, or merging would launder it.
    DB.prepare(
      `UPDATE users SET shadow_banned = 1 WHERE id = ?2
         AND EXISTS (SELECT 1 FROM users WHERE id = ?1 AND is_anonymous = 1 AND shadow_banned = 1)`,
    ).bind(guest.uid, user.uid),
    DB.prepare(`UPDATE game_sessions SET user_id = ?2 WHERE user_id = ?1 AND ${STILL_GUEST}`).bind(guest.uid, user.uid),
    // Guests never have leaderboard rows; this only clears the foreign key before the row goes.
    DB.prepare(`DELETE FROM leaderboard_entries WHERE user_id = ?1 AND ${STILL_GUEST}`).bind(guest.uid),
    DB.prepare("DELETE FROM users WHERE id = ?1 AND is_anonymous = 1").bind(guest.uid),
    ...backfillStatements(DB, user.uid),
  ]);
  const profileRow = (results[0]!.results as RawUser[])[0]!;
  const mergedSessions = results[2]!.meta.changes;
  console.log(JSON.stringify({ requestId: c.get("requestId"), event: "guest_merged", into: user.uid, from: guest.uid, mergedSessions }));
  return c.json({ ...rawProfile(profileRow), mergedSessions });
});
