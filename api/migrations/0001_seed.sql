-- Seed: the 5 generations (year ranges) and 5 genres. Admin-editable afterwards.
-- INSERT OR IGNORE keeps re-running this file harmless.
INSERT OR IGNORE INTO generations (id, slug, name_am, name_en, year_from, year_to, sort) VALUES
  (1, 'golden-age', 'ወርቃማው ዘመን', 'Golden Age', NULL, 1979, 1),
  (2, '80s',        'የ80ዎቹ',        '1980s',      1980, 1989, 2),
  (3, '90s',        'የ90ዎቹ',        '1990s',      1990, 1999, 3),
  (4, '2000s',      'የ2000ዎቹ',      '2000s',      2000, 2009, 4),
  (5, 'modern',     'ዘመናዊ',         'Modern',     2010, NULL, 5);
--> statement-breakpoint
INSERT OR IGNORE INTO genres (id, slug, name_am, name_en) VALUES
  (1, 'tizita',      'ትዝታ',     'Tizita'),
  (2, 'ethio-jazz',  'ኢትዮ ጃዝ',  'Ethio-jazz'),
  (3, 'traditional', 'ባሕላዊ',    'Traditional'),
  (4, 'pop',         'ፖፕ',      'Pop'),
  (5, 'hip-hop',     'ሂፕ ሆፕ',   'Hip-hop');
