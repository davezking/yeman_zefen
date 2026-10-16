// Rebuilds one player's leaderboard rows from their stored sessions. Used when a guest registers
// (POST /v1/me/registered) and after a guest's history is merged into an account (POST /v1/me/merge).
//
// The rows are replaced, not added to, so running it again changes nothing. It counts the same
// sessions POST /v1/sessions does: unflagged, score > 0, and only while the player is registered
// and not shadow-banned. A session's week is the ISO week of `received_at` (the server clock), as
// it is in sessions.ts, so a rebuilt row equals the incrementally built one.
import { ALL_TIME } from "./period";

// The ISO week (`YYYY-Www`) of an epoch-ms column, in plain SQLite date functions (strftime %G/%V
// needs SQLite 3.46, which D1 does not promise). The week's Thursday decides the year; the week
// number is how many weeks that Thursday is into its year. Must match isoWeek() in period.ts.
export function isoWeekSql(msColumn: string): string {
  const day = `date(${msColumn} / 1000, 'unixepoch')`;
  const mondayOffset = `((CAST(strftime('%w', ${day}) AS INTEGER) + 6) % 7)`;
  const thursday = `date(${day}, printf('%+d days', 3 - ${mondayOffset}))`;
  return `printf('%s-W%02d', strftime('%Y', ${thursday}), (CAST(strftime('%j', ${thursday}) AS INTEGER) - 1) / 7 + 1)`;
}

/** Deletes the player's rows. ?1 = user id. */
export const BACKFILL_DELETE_SQL = "DELETE FROM leaderboard_entries WHERE user_id = ?1";

// Each counted session lands in up to four rows: (all, 0), (all, era), (its week, 0), (its week, era).
// json_each supplies the two periods and the two generation choices without a compound SELECT.
/** Inserts the player's rows from their sessions. ?1 = user id. */
export const BACKFILL_INSERT_SQL = `
  INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at)
  SELECT CASE p.value WHEN 0 THEN '${ALL_TIME}' ELSE ${isoWeekSql("s.received_at")} END,
         CASE g.value WHEN 0 THEN 0 ELSE s.generation_id END,
         s.user_id, SUM(s.score), MAX(s.received_at)
    FROM game_sessions s
    JOIN users u ON u.id = s.user_id
    CROSS JOIN json_each('[0,1]') p
    CROSS JOIN json_each('[0,1]') g
   WHERE s.user_id = ?1 AND s.flagged = 0 AND s.score > 0
     AND u.is_anonymous = 0 AND u.shadow_banned = 0 AND u.deleted_at IS NULL
     AND (g.value = 0 OR COALESCE(s.generation_id, 0) <> 0)
   GROUP BY 1, 2`;

/** The two statements, in order, for a batch. */
export function backfillStatements(DB: D1Database, userId: string): D1PreparedStatement[] {
  return [DB.prepare(BACKFILL_DELETE_SQL).bind(userId), DB.prepare(BACKFILL_INSERT_SQL).bind(userId)];
}
