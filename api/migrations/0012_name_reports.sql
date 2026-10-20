PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_review_items` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`entity_type` text NOT NULL,
	`entity_id` integer NOT NULL,
	`entity_ref` text,
	`reason` text NOT NULL,
	`details_json` text,
	`status` text DEFAULT 'open' NOT NULL,
	`resolved_by` text,
	`resolved_at` integer,
	CONSTRAINT "review_items_reason_check" CHECK(reason IN ('translit_uncertain', 'possible_duplicate', 'missing_audio', 'short_audio', 'era_unknown', 'score_anomaly', 'name_report')),
	CONSTRAINT "review_items_status_check" CHECK(status IN ('open', 'resolved', 'dismissed'))
);
--> statement-breakpoint
INSERT INTO `__new_review_items`("id", "entity_type", "entity_id", "entity_ref", "reason", "details_json", "status", "resolved_by", "resolved_at") SELECT "id", "entity_type", "entity_id", "entity_ref", "reason", "details_json", "status", "resolved_by", "resolved_at" FROM `review_items`;--> statement-breakpoint
DROP TABLE `review_items`;--> statement-breakpoint
ALTER TABLE `__new_review_items` RENAME TO `review_items`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `review_items_status_reason_idx` ON `review_items` (`status`,`reason`);--> statement-breakpoint
CREATE INDEX `review_items_entity_idx` ON `review_items` (`entity_type`,`entity_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `review_items_open_ref_uq` ON `review_items` (`entity_type`,`entity_ref`,`reason`) WHERE "review_items"."status" = 'open' AND "review_items"."entity_ref" IS NOT NULL;