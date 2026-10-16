-- Placeholder owner for sessions whose player deleted their account (DELETE /v1/me).
-- game_sessions.user_id is a NOT NULL foreign key to users, so anonymized rows need a user to point at.
-- Shadow-banned so it can never appear on a leaderboard. Firebase UIDs are never 'deleted'; the auth middleware rejects that sub.
INSERT OR IGNORE INTO `users` (`id`, `display_name`, `is_anonymous`, `country`, `created_at`, `last_seen_at`, `shadow_banned`, `deleted_at`)
VALUES ('deleted', NULL, 1, NULL, 0, NULL, 1, 0);
