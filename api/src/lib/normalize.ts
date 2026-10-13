// Comparison-key normalization for artist aliases. Sprint 2 replaces normalizeFidel
// with the full homophone-folding version (docs/architecture.md §4); callers should
// only go through these functions so that swap needs no other change.

const APOSTROPHES = /['’‘ʼʻ`´]/g;
const ETHIOPIC = /[ሀ-᎟ⶀ-⷟꬀-꬯]/;

/** Lowercase, strip diacritics and apostrophes, collapse whitespace. */
export function normalizeLatin(input: string): string {
  return input
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(APOSTROPHES, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/** Stub: NFC + trim. Sprint 2 adds homophone series folding. */
export function normalizeFidel(input: string): string {
  return input.normalize("NFC").trim();
}

/** Picks the normalizer by script: anything containing Ethiopic characters is Fidel. */
export function normalizeAlias(input: string): string {
  return ETHIOPIC.test(input) ? normalizeFidel(input) : normalizeLatin(input);
}
