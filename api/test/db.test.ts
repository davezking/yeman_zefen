import { env } from "cloudflare:workers";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { db } from "../src/db/client";
import { artistAliases, artists, clips, generations, genres, tracks, users } from "../src/db/schema";

const now = 1_760_000_000_000;

/** Drizzle wraps driver errors as "Failed query: ..."; the SQLite message is on `cause`. */
async function expectSqliteError(p: Promise<unknown>, pattern: RegExp) {
  const err = await p.then(
    () => undefined,
    (e: unknown) => e as Error & { cause?: Error },
  );
  expect(err, "expected the statement to be rejected").toBeDefined();
  expect(`${err!.message} ${err!.cause?.message ?? ""}`).toMatch(pattern);
}

async function insertArtist(nameAm: string) {
  const [row] = await db(env)
    .insert(artists)
    .values({ nameAm, nameLatin: "Tilahun Gessesse", createdAt: now, updatedAt: now })
    .returning();
  return row!;
}

describe("seed data", () => {
  it("seeds the 5 generations with year ranges", async () => {
    const rows = await db(env).select().from(generations).orderBy(generations.sort);
    expect(rows.map((r) => [r.slug, r.yearFrom, r.yearTo])).toEqual([
      ["golden-age", null, 1979],
      ["80s", 1980, 1989],
      ["90s", 1990, 1999],
      ["2000s", 2000, 2009],
      ["modern", 2010, null],
    ]);
    expect(rows.every((r) => r.nameAm && r.nameEn)).toBe(true);
  });

  it("seeds the 5 genres", async () => {
    const rows = await db(env).select().from(genres).orderBy(genres.id);
    expect(rows.map((r) => r.slug)).toEqual(["tizita", "ethio-jazz", "traditional", "pop", "hip-hop"]);
  });
});

describe("catalog", () => {
  it("reads an artist + track + clip back with joins", async () => {
    const d = db(env);
    const artist = await insertArtist("ጥላሁን ገሠሠ");
    const [golden] = await d.select().from(generations).where(eq(generations.slug, "golden-age"));
    const [track] = await d
      .insert(tracks)
      .values({
        artistId: artist.id,
        titleAm: "ትዝታ",
        titleLatin: "Tizita",
        releaseYear: 1975,
        generationId: golden!.id,
        createdAt: now,
        updatedAt: now,
      })
      .returning();
    await d.insert(clips).values({ trackId: track!.id, type: "intro", startMs: 0 });

    const rows = await d
      .select({
        artist: artists.nameAm,
        title: tracks.titleLatin,
        status: tracks.status,
        generation: generations.slug,
        clipType: clips.type,
        clipLengthMs: clips.lengthMs,
        clipStatus: clips.status,
      })
      .from(tracks)
      .innerJoin(artists, eq(tracks.artistId, artists.id))
      .innerJoin(generations, eq(tracks.generationId, generations.id))
      .innerJoin(clips, eq(clips.trackId, tracks.id))
      .where(eq(tracks.id, track!.id));

    expect(rows).toEqual([
      {
        artist: "ጥላሁን ገሠሠ",
        title: "Tizita",
        status: "ingested",
        generation: "golden-age",
        clipType: "intro",
        clipLengthMs: 10000,
        clipStatus: "pending",
      },
    ]);
  });

  it("rejects a duplicate alias_norm", async () => {
    const d = db(env);
    const a = await insertArtist("አስቴር አወቀ");
    const b = await insertArtist("መሐሙድ አሕመድ");
    await d.insert(artistAliases).values({ artistId: a.id, alias: "Aster Aweke", aliasNorm: "aster aweke" });
    await expectSqliteError(
      d.insert(artistAliases).values({ artistId: b.id, alias: "Aster  Aweke", aliasNorm: "aster aweke" }),
      /UNIQUE/i,
    );
  });

  it("rejects a duplicate artists.name_am", async () => {
    await insertArtist("ሙላቱ አስታጥቄ");
    await expectSqliteError(insertArtist("ሙላቱ አስታጥቄ"), /UNIQUE/i);
  });

  it("rejects an invalid track status and a dangling artist_id", async () => {
    const d = db(env);
    const artist = await insertArtist("ኤልያስ መልካ");
    await expectSqliteError(
      d.run(
        sql`INSERT INTO tracks (artist_id, status, created_at, updated_at) VALUES (${artist.id}, 'bogus', ${now}, ${now})`,
      ),
      /CHECK/i,
    );
    await expectSqliteError(
      d.insert(tracks).values({ artistId: 999_999, createdAt: now, updatedAt: now }),
      /FOREIGN KEY/i,
    );
  });

  it("allows one clip per (track, type)", async () => {
    const d = db(env);
    const artist = await insertArtist("ማሪማ");
    const [track] = await d
      .insert(tracks)
      .values({ artistId: artist.id, createdAt: now, updatedAt: now })
      .returning();
    await d.insert(clips).values({ trackId: track!.id, type: "middle", startMs: 60_000 });
    await expectSqliteError(d.insert(clips).values({ trackId: track!.id, type: "middle", startMs: 70_000 }), /UNIQUE/i);
  });
});

describe("indexes", () => {
  it("creates the required indexes, including leaderboard points DESC", async () => {
    const rows = await env.DB.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'index'").all<{
      name: string;
      sql: string | null;
    }>();
    const names = rows.results.map((r) => r.name);
    for (const idx of [
      "tracks_status_idx",
      "tracks_artist_id_idx",
      "tracks_generation_id_idx",
      "review_items_status_reason_idx",
      "game_sessions_user_received_idx",
      "game_sessions_received_idx",
      "leaderboard_period_gen_points_idx",
    ]) {
      expect(names).toContain(idx);
    }
    const lb = rows.results.find((r) => r.name === "leaderboard_period_gen_points_idx");
    expect(lb?.sql).toMatch(/"points" DESC/);
  });

  it("enforces composite primary keys on leaderboard_entries and royalty_daily", async () => {
    const d = db(env);
    await d.insert(users).values({ id: "uid-1", createdAt: now });
    const lb = sql`INSERT INTO leaderboard_entries (period, generation_id, user_id, points, updated_at) VALUES ('all', 0, 'uid-1', 10, ${now})`;
    await d.run(lb);
    await expectSqliteError(d.run(lb), /UNIQUE|PRIMARY/i);
  });
});
