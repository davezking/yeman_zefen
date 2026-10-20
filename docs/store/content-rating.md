# Content rating: questionnaire answers (draft)

Answers for the IARC questionnaire in Play Console (Policy > App content > Content rating) and the age-rating
questionnaire in App Store Connect. The questions change over time, so the on-screen wording may differ. Confirm
each answer against the current form. Answers are for a **game that plays licensed Amharic songs, with ads, and has
no chat**. If any song's lyrics are sensitive, see the note at the end.

## Google Play (IARC)

| Topic | Answer | Why |
|---|---|---|
| Violence (realistic, fantasy, cartoon) | No | No violence in the game. |
| Sexual content or nudity | No | None. |
| Language (profanity, crude humor) | No | The app has no user chat; song titles and artist names come from the catalog. (confirm after the catalog review) |
| Controlled substances (drugs, alcohol, tobacco) | No | None in the game itself. (confirm after lyric review) |
| Gambling (real or simulated) | No | No real money. The points do not convert to money. |
| Does the app allow users to interact or exchange information? | **Yes**: players choose a display name, which other players see on the leaderboards with their country. There is no chat or messaging. | Display names are text that players write and others read, so answer yes rather than leave it out. |
| Does the app share the user's location with other users? | No | Only the country shown in statistics. |
| Does the app contain user-generated content? | Yes, limited to display names | Names are checked against a blocklist on the server, and administrators can hide a player from others' leaderboards. No posts or uploads. |
| Does the app contain ads? | **Yes** | Interstitial and rewarded ads from Google AdMob. |
| Does the app allow purchases? | No | |

Expected rating: a low, general-audience rating (for example "Everyone"). The rating is set by IARC, not by us.

## Apple (age rating)

| Question | Answer |
|---|---|
| Cartoon or fantasy violence, realistic violence, prolonged graphic or sadistic violence | None |
| Profanity or crude humor, mature or suggestive themes, horror or fear themes | None (confirm for lyrics) |
| Medical or treatment information, alcohol, tobacco or drug use or references | None (confirm for lyrics) |
| Sexual content or nudity | None |
| Gambling and contests | No (no real-money gambling; no contests) |
| Unrestricted web access | No |
| User-generated content | Yes, display names only (blocklist on the server, administrators can hide a player; see `review-notes.md`) |
| Messaging and chat | No |
| Advertising | **Yes** (AdMob ads) |
| Made for kids | No |

Expected rating: 4+. Apple computes the rating from these answers; confirm the result in App Store Connect.

## Note on lyrics

Several Amharic songs may have lyrics about alcohol, love or other mature themes. The game shows only titles and artist
names, and plays short clips. If the music association's catalog review finds lyrics that a store would treat as
mature, change the lyric-related answers to match, rather than hiding the answer.
