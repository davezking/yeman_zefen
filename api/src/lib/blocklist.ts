// Display names that are not allowed. Matching is case-insensitive and ignores spaces,
// so "Ad Min" is caught by "admin". A name is rejected if it *contains* any entry.
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
  "yemanzefen",
  "የማንዘፈን",
  // Common English profanity
  "fuck",
  "shit",
  "bitch",
  "asshole",
];

/** Lowercase, drop spaces, so " Ad Min " compares equal to "admin". */
function squash(name: string): string {
  return name.toLowerCase().replace(/\s+/gu, "");
}

export function isBlockedDisplayName(name: string, blocklist: readonly string[] = DISPLAY_NAME_BLOCKLIST): boolean {
  const squashed = squash(name);
  return blocklist.some((term) => term !== "" && squashed.includes(squash(term)));
}
