// D1 schema. Spec: docs/architecture.md §4. All timestamps are integer epoch ms, UTC.
import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
  type AnySQLiteColumn,
} from "drizzle-orm/sqlite-core";

const inList = (col: string, values: readonly string[]) =>
  sql.raw(`${col} IN (${values.map((v) => `'${v}'`).join(", ")})`);

export const TRACK_STATUSES = ["ingested", "needs_review", "approved", "rejected", "retired"] as const;
/** A track with one of these statuses is out of the catalog: nothing about it is left to review. */
export const OUT_OF_CATALOG = ["rejected", "retired"] as const;
export const CLIP_TYPES = ["intro", "middle"] as const;
export const CLIP_STATUSES = ["pending", "ready", "failed"] as const;
export const REVIEW_REASONS = [
  "translit_uncertain",
  "possible_duplicate",
  "missing_audio",
  "short_audio",
  "era_unknown",
] as const;
export const REVIEW_STATUSES = ["open", "resolved", "dismissed"] as const;
export const ADMIN_ROLES = ["admin", "editor"] as const;
export const INGEST_KINDS = ["scrape", "cut", "recut"] as const;
export const INGEST_STATUSES = ["queued", "running", "succeeded", "failed"] as const;

export const artists = sqliteTable("artists", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  nameAm: text("name_am").notNull().unique(),
  nameLatin: text("name_latin"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
});

export const artistAliases = sqliteTable(
  "artist_aliases",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    artistId: integer("artist_id")
      .notNull()
      .references(() => artists.id, { onDelete: "cascade" }),
    alias: text("alias").notNull(),
    aliasNorm: text("alias_norm").notNull().unique(),
    source: text("source"),
  },
  (t) => [index("artist_aliases_artist_id_idx").on(t.artistId)],
);

export const generations = sqliteTable("generations", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  slug: text("slug").notNull().unique(),
  nameAm: text("name_am").notNull(),
  nameEn: text("name_en").notNull(),
  yearFrom: integer("year_from"),
  yearTo: integer("year_to"),
  sort: integer("sort").notNull(),
});

export const genres = sqliteTable("genres", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  slug: text("slug").notNull().unique(),
  nameAm: text("name_am").notNull(),
  nameEn: text("name_en").notNull(),
});

export const tracks = sqliteTable(
  "tracks",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    artistId: integer("artist_id")
      .notNull()
      .references(() => artists.id),
    titleAm: text("title_am"),
    titleLatin: text("title_latin"),
    album: text("album"),
    releaseYear: integer("release_year"),
    generationId: integer("generation_id").references(() => generations.id),
    generationOverridden: integer("generation_overridden", { mode: "boolean" }).notNull().default(false),
    sourceUrl: text("source_url"),
    sourceAudioKey: text("source_audio_key"),
    durationMs: integer("duration_ms"),
    /** JSON array of field names an admin has edited; re-scrapes never overwrite these. */
    adminEditedFields: text("admin_edited_fields").notNull().default("[]"),
    status: text("status", { enum: TRACK_STATUSES }).notNull().default("ingested"),
    canonicalTrackId: integer("canonical_track_id").references((): AnySQLiteColumn => tracks.id),
    createdAt: integer("created_at").notNull(),
    updatedAt: integer("updated_at").notNull(),
  },
  (t) => [
    index("tracks_status_idx").on(t.status),
    index("tracks_artist_id_idx").on(t.artistId),
    index("tracks_generation_id_idx").on(t.generationId),
    // The ingest upsert key. NULLs are allowed (and distinct) for hand-created tracks.
    uniqueIndex("tracks_source_url_uq").on(t.sourceUrl),
    // "Is any track a duplicate of this one?" (mark-duplicate keeps links one level deep).
    index("tracks_canonical_track_id_idx").on(t.canonicalTrackId),
    check("tracks_status_check", inList("status", TRACK_STATUSES)),
  ],
);

export const trackGenres = sqliteTable(
  "track_genres",
  {
    trackId: integer("track_id")
      .notNull()
      .references(() => tracks.id, { onDelete: "cascade" }),
    genreId: integer("genre_id")
      .notNull()
      .references(() => genres.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.trackId, t.genreId] }), index("track_genres_genre_id_idx").on(t.genreId)],
);

export const clips = sqliteTable(
  "clips",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    trackId: integer("track_id")
      .notNull()
      .references(() => tracks.id, { onDelete: "cascade" }),
    type: text("type", { enum: CLIP_TYPES }).notNull(),
    startMs: integer("start_ms").notNull(),
    lengthMs: integer("length_ms").notNull().default(10000),
    r2Key: text("r2_key"),
    sha256: text("sha256"),
    bytes: integer("bytes"),
    version: integer("version").notNull().default(1),
    status: text("status", { enum: CLIP_STATUSES }).notNull().default("pending"),
  },
  (t) => [
    // One row per (track, type); a recut bumps `version` in place.
    uniqueIndex("clips_track_type_uq").on(t.trackId, t.type),
    check("clips_type_check", inList("type", CLIP_TYPES)),
    check("clips_status_check", inList("status", CLIP_STATUSES)),
  ],
);

export const reviewItems = sqliteTable(
  "review_items",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    // Polymorphic (track / artist), so no FK.
    entityType: text("entity_type").notNull(),
    entityId: integer("entity_id").notNull(),
    reason: text("reason", { enum: REVIEW_REASONS }).notNull(),
    detailsJson: text("details_json"),
    status: text("status", { enum: REVIEW_STATUSES }).notNull().default("open"),
    resolvedBy: text("resolved_by"),
    resolvedAt: integer("resolved_at"),
  },
  (t) => [
    index("review_items_status_reason_idx").on(t.status, t.reason),
    // Per-entity lookups (ingest de-duplication, a track's open items) must not scan the whole queue.
    index("review_items_entity_idx").on(t.entityType, t.entityId),
    check("review_items_reason_check", inList("reason", REVIEW_REASONS)),
    check("review_items_status_check", inList("status", REVIEW_STATUSES)),
  ],
);

export const packs = sqliteTable("packs", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  slug: text("slug").notNull().unique(),
  nameAm: text("name_am").notNull(),
  nameEn: text("name_en").notNull(),
  generationId: integer("generation_id").references(() => generations.id),
  genreId: integer("genre_id").references(() => genres.id),
  currentVersion: integer("current_version"),
});

export const packVersions = sqliteTable(
  "pack_versions",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    packId: integer("pack_id")
      .notNull()
      .references(() => packs.id, { onDelete: "cascade" }),
    version: integer("version").notNull(),
    manifestKey: text("manifest_key").notNull(),
    trackCount: integer("track_count").notNull(),
    totalBytes: integer("total_bytes").notNull(),
    publishedAt: integer("published_at").notNull(),
    publishedBy: text("published_by"),
  },
  (t) => [uniqueIndex("pack_versions_pack_version_uq").on(t.packId, t.version)],
);

export const packTracks = sqliteTable(
  "pack_tracks",
  {
    packVersionId: integer("pack_version_id")
      .notNull()
      .references(() => packVersions.id, { onDelete: "cascade" }),
    trackId: integer("track_id")
      .notNull()
      .references(() => tracks.id),
    introClipId: integer("intro_clip_id").references(() => clips.id),
    middleClipId: integer("middle_clip_id").references(() => clips.id),
  },
  (t) => [primaryKey({ columns: [t.packVersionId, t.trackId] }), index("pack_tracks_track_id_idx").on(t.trackId)],
);

export const users = sqliteTable("users", {
  /** Firebase UID. */
  id: text("id").primaryKey(),
  displayName: text("display_name"),
  isAnonymous: integer("is_anonymous", { mode: "boolean" }).notNull().default(true),
  country: text("country"),
  createdAt: integer("created_at").notNull(),
  lastSeenAt: integer("last_seen_at"),
  shadowBanned: integer("shadow_banned", { mode: "boolean" }).notNull().default(false),
  deletedAt: integer("deleted_at"),
});

export const gameSessions = sqliteTable(
  "game_sessions",
  {
    /** Client-generated UUID; the idempotency key. */
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id),
    mode: text("mode").notNull(),
    /** 0 = all generations (matches leaderboard_entries). */
    generationId: integer("generation_id"),
    difficulty: text("difficulty"),
    clientStartedAt: integer("client_started_at"),
    receivedAt: integer("received_at").notNull(),
    rounds: integer("rounds").notNull(),
    score: integer("score").notNull(),
    trackIdsJson: text("track_ids_json").notNull(),
    eventsJson: text("events_json").notNull(),
    offline: integer("offline", { mode: "boolean" }).notNull().default(false),
    country: text("country"),
    flagged: integer("flagged", { mode: "boolean" }).notNull().default(false),
    flagReason: text("flag_reason"),
  },
  (t) => [
    index("game_sessions_user_received_idx").on(t.userId, t.receivedAt),
    index("game_sessions_received_idx").on(t.receivedAt),
  ],
);

export const leaderboardEntries = sqliteTable(
  "leaderboard_entries",
  {
    /** `all` or an ISO week such as `2026-W42`. */
    period: text("period").notNull(),
    /** 0 = all generations. */
    generationId: integer("generation_id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => users.id),
    points: integer("points").notNull().default(0),
    updatedAt: integer("updated_at").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.period, t.generationId, t.userId] }),
    index("leaderboard_period_gen_points_idx").on(t.period, t.generationId, sql`${t.points} DESC`),
  ],
);

export const royaltyDaily = sqliteTable(
  "royalty_daily",
  {
    /** UTC day, `YYYY-MM-DD`. */
    date: text("date").notNull(),
    trackId: integer("track_id")
      .notNull()
      .references(() => tracks.id),
    plays: integer("plays").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.date, t.trackId] })],
);

export const adEventsDaily = sqliteTable(
  "ad_events_daily",
  {
    date: text("date").notNull(),
    country: text("country").notNull(),
    format: text("format").notNull(),
    event: text("event").notNull(),
    count: integer("count").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.date, t.country, t.format, t.event] })],
);

export const analyticsDaily = sqliteTable(
  "analytics_daily",
  {
    date: text("date").notNull(),
    metric: text("metric").notNull(),
    dimension: text("dimension").notNull().default(""),
    value: integer("value").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.date, t.metric, t.dimension] })],
);

export const adminUsers = sqliteTable(
  "admin_users",
  {
    email: text("email").primaryKey(),
    role: text("role", { enum: ADMIN_ROLES }).notNull(),
    createdAt: integer("created_at").notNull(),
  },
  () => [check("admin_users_role_check", inList("role", ADMIN_ROLES))],
);

export const ingestJobs = sqliteTable(
  "ingest_jobs",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    kind: text("kind", { enum: INGEST_KINDS }).notNull(),
    status: text("status", { enum: INGEST_STATUSES }).notNull().default("queued"),
    paramsJson: text("params_json"),
    ghRunUrl: text("gh_run_url"),
    startedAt: integer("started_at"),
    finishedAt: integer("finished_at"),
    summaryJson: text("summary_json"),
  },
  () => [
    check("ingest_jobs_kind_check", inList("kind", INGEST_KINDS)),
    check("ingest_jobs_status_check", inList("status", INGEST_STATUSES)),
  ],
);
