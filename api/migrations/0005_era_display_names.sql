-- English era names follow the app design (docs/design/copy.md): "The '80s", not "1980s".
-- Only rows still holding the seeded name change, so an admin's own edit is kept.
UPDATE generations SET name_en = 'The ''80s' WHERE id = 2 AND name_en = '1980s';
--> statement-breakpoint
UPDATE generations SET name_en = 'The ''90s' WHERE id = 3 AND name_en = '1990s';
--> statement-breakpoint
UPDATE generations SET name_en = 'The 2000s' WHERE id = 4 AND name_en = '2000s';
