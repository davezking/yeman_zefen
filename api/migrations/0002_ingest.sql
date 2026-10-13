ALTER TABLE `tracks` ADD `admin_edited_fields` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `tracks_source_url_uq` ON `tracks` (`source_url`);