import { z } from "zod";
import { isBlockedDisplayName } from "./blocklist";

export const DISPLAY_NAME_MIN = 2;
export const DISPLAY_NAME_MAX = 24;

// A character is allowed when it is a Fidel letter, a Latin letter (A-Z, a-z), a digit, or a space.
// Ethiopic punctuation and numerals are in the Ethiopic script too, so require \p{L} for those.
const ETHIOPIC = /^\p{Script=Ethiopic}$/u;
const LETTER = /^\p{L}$/u;
const isFidelLetter = (ch: string) => ETHIOPIC.test(ch) && LETTER.test(ch);
const LATIN_OR_DIGIT = /^[A-Za-z0-9 ]$/u;

/**
 * A player-chosen display name: 2-24 characters of Fidel or Latin letters, digits and spaces,
 * not on the blocklist. Normalized to NFC with surrounding space trimmed and runs of spaces
 * collapsed, so what is stored is what the client reads back.
 */
export const displayNameSchema = z
  .string()
  .transform((s) => s.normalize("NFC").trim().replace(/ {2,}/g, " "))
  .pipe(
    z
      .string()
      .refine((s) => [...s].length >= DISPLAY_NAME_MIN, `must be at least ${DISPLAY_NAME_MIN} characters`)
      .refine((s) => [...s].length <= DISPLAY_NAME_MAX, `must be at most ${DISPLAY_NAME_MAX} characters`)
      .refine(
        (s) => [...s].every((ch) => LATIN_OR_DIGIT.test(ch) || isFidelLetter(ch)),
        "may only contain Amharic or Latin letters, digits and spaces",
      )
      .refine((s) => !isBlockedDisplayName(s), "is not allowed"),
  );
