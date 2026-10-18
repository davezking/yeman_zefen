CREATE TABLE `moderation_log` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`at` integer NOT NULL,
	`admin_email` text NOT NULL,
	`action` text NOT NULL,
	`user_id` text,
	`session_id` text,
	`review_item_id` integer,
	`note` text NOT NULL,
	`details_json` text,
	CONSTRAINT "moderation_log_action_check" CHECK(action IN ('shadow_ban', 'shadow_unban', 'void_session', 'dismiss_session', 'dismiss_flag', 'resolve_flag'))
);
--> statement-breakpoint
CREATE INDEX `moderation_log_user_at_idx` ON `moderation_log` (`user_id`,`at`);--> statement-breakpoint
CREATE UNIQUE INDEX `moderation_log_session_uq` ON `moderation_log` (`session_id`,`action`) WHERE "moderation_log"."action" IN ('void_session', 'dismiss_session');--> statement-breakpoint
CREATE INDEX `game_sessions_flagged_idx` ON `game_sessions` (`received_at`) WHERE "game_sessions"."flagged" = 1;