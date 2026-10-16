// Display names that are not allowed. A name is blocked when a term matches one of its
// words, or a run of adjacent words read together ("Ad Min", "Yeman Zefen"), ignoring
// case and trailing digits ("Admin2"). Terms are matched against whole words only, never
// substrings, so real names that merely contain a term (Shitaye, Badminton,
// "Ahmad Mintesinot") are not caught.
//
// This is the starter list. Add terms here (Amharic and Latin) as moderation needs them;
// it is a plain array so an admin can extend it with a one-line change.
// TODO: have a native Amharic speaker add Fidel profanity (the same review as the display-name strings).
export const DISPLAY_NAME_BLOCKLIST: readonly string[] = [
  // Impersonation
  "admin",
  "moderator",
  "support",
  "official",
  "yeman zefen",
  "የማን ዘፈን",
  // Common English profanity
  "fuck",
  "shit",
  "bitch",
  "asshole",
];

/** Lowercase, drop spaces and trailing digits, so "Ad Min 2" compares equal to "admin". */
function squash(text: string): string {
  return text.toLowerCase().replace(/\s+/gu, "").replace(/\d+$/u, "");
}

const SQUASHED = new Set(DISPLAY_NAME_BLOCKLIST.map(squash).filter((t) => t !== ""));

export function isBlockedDisplayName(name: string, blocklist: ReadonlySet<string> = SQUASHED): boolean {
  const words = name.toLowerCase().split(/\s+/u).filter(Boolean);
  // Every run of adjacent words, joined. Names are at most 24 characters, so this stays tiny.
  for (let start = 0; start < words.length; start++) {
    let run = "";
    for (let end = start; end < words.length; end++) {
      run += words[end];
      if (blocklist.has(squash(run))) return true;
    }
  }
  return false;
}
