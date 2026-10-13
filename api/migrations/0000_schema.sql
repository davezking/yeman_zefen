CREATE TABLE `ad_events_daily` (
	`date` text NOT NULL,
	`country` text NOT NULL,
	`format` text NOT NULL,
	`event` text NOT NULL,
	`count` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`date`, `country`, `format`, `event`)
);
--> statement-breakpoint
CREATE TABLE `admin_users` (
	`email` text PRIMARY KEY NOT NULL,
	`role` text NOT NULL,
	`created_at` integer NOT NULL,
	CONSTRAINT "admin_users_role_check" CHECK(role IN ('admin', 'editor'))
);
--> statement-breakpoint
CREATE TABLE `analytics_daily` (
	`date` text NOT NULL,
	`metric` text NOT NULL,
	`dimension` text DEFAULT '' NOT NULL,
	`value` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`date`, `metric`, `dimension`)
);
--> statement-breakpoint
CREATE TABLE `artist_aliases` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`artist_id` integer NOT NULL,
	`alias` text NOT NULL,
	`alias_norm` text NOT NULL,
	`source` text,
	FOREIGN KEY (`artist_id`) REFERENCES `artists`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `artist_aliases_alias_norm_unique` ON `artist_aliases` (`alias_norm`);--> statement-breakpoint
CREATE INDEX `artist_aliases_artist_id_idx` ON `artist_aliases` (`artist_id`);--> statement-breakpoint
CREATE TABLE `artists` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name_am` text NOT NULL,
	`name_latin` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `artists_name_am_unique` ON `artists` (`name_am`);--> statement-breakpoint
CREATE TABLE `clips` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`track_id` integer NOT NULL,
	`type` text NOT NULL,
	`start_ms` integer NOT NULL,
	`length_ms` integer DEFAULT 10000 NOT NULL,
	`r2_key` text,
	`sha256` text,
	`bytes` integer,
	`version` integer DEFAULT 1 NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	FOREIGN KEY (`track_id`) REFERENCES `tracks`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "clips_type_check" CHECK(type IN ('intro', 'middle')),
	CONSTRAINT "clips_status_check" CHECK(status IN ('pending', 'ready', 'failed'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `clips_track_type_uq` ON `clips` (`track_id`,`type`);--> statement-breakpoint
CREATE TABLE `game_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`mode` text NOT NULL,
	`generation_id` integer,
	`difficulty` text,
	`client_started_at` integer,
	`received_at` integer NOT NULL,
	`rounds` integer NOT NULL,
	`score` integer NOT NULL,
	`track_ids_json` text NOT NULL,
	`events_json` text NOT NULL,
	`offline` integer DEFAULT false NOT NULL,
	`country` text,
	`flagged` integer DEFAULT false NOT NULL,
	`flag_reason` text,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `game_sessions_user_received_idx` ON `game_sessions` (`user_id`,`received_at`);--> statement-breakpoint
CREATE INDEX `game_sessions_received_idx` ON `game_sessions` (`received_at`);--> statement-breakpoint
CREATE TABLE `generations` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`name_am` text NOT NULL,
	`name_en` text NOT NULL,
	`year_from` integer,
	`year_to` integer,
	`sort` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `generations_slug_unique` ON `generations` (`slug`);--> statement-breakpoint
CREATE TABLE `genres` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`name_am` text NOT NULL,
	`name_en` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `genres_slug_unique` ON `genres` (`slug`);--> statement-breakpoint
CREATE TABLE `ingest_jobs` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`kind` text NOT NULL,
	`status` text DEFAULT 'queued' NOT NULL,
	`params_json` text,
	`gh_run_url` text,
	`started_at` integer,
	`finished_at` integer,
	`summary_json` text,
	CONSTRAINT "ingest_jobs_kind_check" CHECK(kind IN ('scrape', 'cut', 'recut')),
	CONSTRAINT "ingest_jobs_status_check" CHECK(status IN ('queued', 'running', 'succeeded', 'failed'))
);
--> statement-breakpoint
CREATE TABLE `leaderboard_entries` (
	`period` text NOT NULL,
	`generation_id` integer NOT NULL,
	`user_id` text NOT NULL,
	`points` integer DEFAULT 0 NOT NULL,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`period`, `generation_id`, `user_id`),
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `leaderboard_period_gen_points_idx` ON `leaderboard_entries` (`period`,`generation_id`,"points" DESC);--> statement-breakpoint
CREATE TABLE `pack_tracks` (
	`pack_version_id` integer NOT NULL,
	`track_id` integer NOT NULL,
	`intro_clip_id` integer,
	`middle_clip_id` integer,
	PRIMARY KEY(`pack_version_id`, `track_id`),
	FOREIGN KEY (`pack_version_id`) REFERENCES `pack_versions`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`track_id`) REFERENCES `tracks`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`intro_clip_id`) REFERENCES `clips`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`middle_clip_id`) REFERENCES `clips`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `pack_tracks_track_id_idx` ON `pack_tracks` (`track_id`);--> statement-breakpoint
CREATE TABLE `pack_versions` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`pack_id` integer NOT NULL,
	`version` integer NOT NULL,
	`manifest_key` text NOT NULL,
	`track_count` integer NOT NULL,
	`total_bytes` integer NOT NULL,
	`published_at` integer NOT NULL,
	`published_by` text,
	FOREIGN KEY (`pack_id`) REFERENCES `packs`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `pack_versions_pack_version_uq` ON `pack_versions` (`pack_id`,`version`);--> statement-breakpoint
CREATE TABLE `packs` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`slug` text NOT NULL,
	`name_am` text NOT NULL,
	`name_en` text NOT NULL,
	`generation_id` integer,
	`genre_id` integer,
	`current_version` integer,
	FOREIGN KEY (`generation_id`) REFERENCES `generations`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`genre_id`) REFERENCES `genres`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `packs_slug_unique` ON `packs` (`slug`);--> statement-breakpoint
CREATE TABLE `review_items` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`entity_type` text NOT NULL,
	`entity_id` integer NOT NULL,
	`reason` text NOT NULL,
	`details_json` text,
	`status` text DEFAULT 'open' NOT NULL,
	`resolved_by` text,
	`resolved_at` integer,
	CONSTRAINT "review_items_reason_check" CHECK(reason IN ('translit_uncertain', 'possible_duplicate', 'missing_audio', 'short_audio', 'era_unknown')),
	CONSTRAINT "review_items_status_check" CHECK(status IN ('open', 'resolved', 'dismissed'))
);
--> statement-breakpoint
CREATE INDEX `review_items_status_reason_idx` ON `review_items` (`status`,`reason`);--> statement-breakpoint
CREATE TABLE `royalty_daily` (
	`date` text NOT NULL,
	`track_id` integer NOT NULL,
	`plays` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`date`, `track_id`),
	FOREIGN KEY (`track_id`) REFERENCES `tracks`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `track_genres` (
	`track_id` integer NOT NULL,
	`genre_id` integer NOT NULL,
	PRIMARY KEY(`track_id`, `genre_id`),
	FOREIGN KEY (`track_id`) REFERENCES `tracks`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`genre_id`) REFERENCES `genres`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `track_genres_genre_id_idx` ON `track_genres` (`genre_id`);--> statement-breakpoint
CREATE TABLE `tracks` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`artist_id` integer NOT NULL,
	`title_am` text,
	`title_latin` text,
	`album` text,
	`release_year` integer,
	`generation_id` integer,
	`generation_overridden` integer DEFAULT false NOT NULL,
	`source_url` text,
	`source_audio_key` text,
	`duration_ms` integer,
	`status` text DEFAULT 'ingested' NOT NULL,
	`canonical_track_id` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`artist_id`) REFERENCES `artists`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`generation_id`) REFERENCES `generations`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`canonical_track_id`) REFERENCES `tracks`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "tracks_status_check" CHECK(status IN ('ingested', 'needs_review', 'approved', 'rejected', 'retired'))
);
--> statement-breakpoint
CREATE INDEX `tracks_status_idx` ON `tracks` (`status`);--> statement-breakpoint
CREATE INDEX `tracks_artist_id_idx` ON `tracks` (`artist_id`);--> statement-breakpoint
CREATE INDEX `tracks_generation_id_idx` ON `tracks` (`generation_id`);--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`display_name` text,
	`is_anonymous` integer DEFAULT true NOT NULL,
	`country` text,
	`created_at` integer NOT NULL,
	`last_seen_at` integer,
	`shadow_banned` integer DEFAULT false NOT NULL,
	`deleted_at` integer
);
