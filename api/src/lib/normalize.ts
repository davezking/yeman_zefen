// Comparison-key normalization for artist aliases (docs/architecture.md §4, "Amharic normalization").
// Mirrors ingest/yz/fidel.py; both are run against docs/fixtures/normalize.json and must give
// identical output. The folded form is only a comparison key: stored names keep the spelling the
// admin or the source chose (use cleanText for those). Callers should only go through these functions.

// Whitespace is listed explicitly rather than with \s, because JavaScript's and Python's \s differ.
const WHITESPACE = /[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+/g;
const APOSTROPHES = /['’‘ʼʻ`´]/g;
const ETHIOPIC = /[ሀ-᎟ⶀ-⷟꬀-꬯]/;

/** Homophone series folded onto one form, each across the seven orders and the 8th ("wa") member. */
const FOLD_RANGES: readonly (readonly [first: number, last: number, shift: number])[] = [
  [0x1210, 0x1217, -0x10], // ሐ -> ሀ
  [0x1280, 0x1287, -0x80], // ኀ -> ሀ
  [0x1220, 0x1227, +0x10], // ሠ -> ሰ
  [0x12d0, 0x12d6, -0x30], // ዐ -> አ
  [0x1340, 0x1347, -0x08], // ፀ -> ጸ
];

function foldChar(ch: string): string {
  const cp = ch.codePointAt(0)!;
  for (const [first, last, shift] of FOLD_RANGES) {
    if (cp >= first && cp <= last) return String.fromCodePoint(cp + shift);
  }
  return ch;
}

const collapse = (s: string) => s.replace(WHITESPACE, " ").replace(/^ | $/g, "");

/** NFC, collapse whitespace, trim. Keeps the spelling: this is the form that gets stored. */
export function cleanText(input: string): string {
  return collapse(input.normalize("NFC"));
}

/** Lowercase, strip diacritics and apostrophes, collapse whitespace. */
export function normalizeLatin(input: string): string {
  return collapse(
    input
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .replace(APOSTROPHES, "")
      .toLowerCase(),
  );
}

/** Comparison key for a Fidel string: cleanText, then the homophone series folded. */
export function normalizeFidel(input: string): string {
  return Array.from(cleanText(input), foldChar).join("");
}

/** Picks the normalizer by script: anything containing Ethiopic characters is Fidel. */
export function normalizeAlias(input: string): string {
  return ETHIOPIC.test(input) ? normalizeFidel(input) : normalizeLatin(input);
}
