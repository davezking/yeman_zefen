# Copy: English and Amharic strings

Every user-facing string in the app, keyed for the Flutter ARB files (`app_en.arb`, `app_am.arb`). The hi-fi screens in `artifacts/` use these strings; where a screen shows sample data (names, scores, sizes), the key with its `{placeholder}` is what ships.

**Amharic status: reviewed by a native speaker.** Keep it that way: have any new or changed Amharic string reviewed before it ships.

## Rules

- **Keys** are `area.item[.detail]`, lowerCamelCase segments. In ARB, replace the dots with nothing and capitalize each segment (`round.hint.watch` → `roundHintWatch`), or keep a lookup table; pick one in Sprint 2 and stick to it.
- **Placeholders** are ICU: `{name}` for a value, `{count, plural, …}` where English needs a plural. Amharic plural forms are written out where they differ (`settings.offline`). Numbers are formatted with the locale's grouping (`1,240`).
- **Amharic register** is the polite form throughout (ይ- imperatives: ይመለሱ, ይጫወቱ, ይግቡ). Never the familiar form.
- **Numerals and dates**: Arabic numerals and Gregorian years in both languages (`የ80ዎቹ`, `ከ1980 በፊት`).
- **Units**: `s` / `ሰከንድ`, `MB` / `ሜባ`, `pts` / `ነጥብ`, with a space before the unit.
- **Song and artist names** come from the catalog, not this file: tracks have `title_am` and `title_latin`, artists have `name_am` and `name_en`. Show the Amharic field in Amharic and the Latin/English field in English, falling back to the other if one is missing. Never transliterate at runtime.
- **No emoji.** Icons are drawn, not typed.
- **Production-only strings** (service errors, pack states, session problems) are not in the copy deck. Their Amharic text in `app/lib/l10n/app_am.arb` was written by Claude and its `@key` description starts with `REVIEW`, so the native-speaker pass can find them with `grep -c REVIEW app/lib/l10n/app_am.arb`. Remove the `REVIEW` marker once a speaker has approved the text.
- **Brand terms** stay in Latin script inside Amharic: Google, Apple, Google Play, App Store.

## Changes since the Step 1 copy deck

The Step 1 deck on the canvas is superseded by this file. Step 4 and the play-first architecture (`docs/architecture.md`, "Play-first delivery") changed:

- **Navigation:** the bottom bar is Home · Play · Settings. `nav.leaderboard` is gone; the leaderboard opens from a Home row (`home.leaderboard*`). Added `nav.play`, `home.hello`, `home.best.label` (replaces `home.best`), `home.quickPlay.label`, and the short mode descriptions for Home.
- **Round:** `round.timerPaused` is just "Paused". Added `round.hint.button`, `round.loading.note` (the 10 s next-song wait).
- **Feedback:** `feedback.reveal` uses a middle dot instead of "by" (fits one line). `feedback.tapToContinue` carries the countdown.
- **Offline play:** two toggles (packs on Wi-Fi only; upcoming songs on mobile data), cache size and Clear cache, per the architecture.
- **Errors:** the "next song didn't load" screen (`error.nextSong.*`) is removed. The architecture waits up to 10 s and then skips the round (`round.loading.note`, `feedback.skipped`). The "no packs" empty state (`empty.packs.*`) is replaced by "out of songs" (`empty.outOfSongs.*`), because built-in songs always exist.
- **Removed** `home.offlineMore.*` and `mode.needsPack`: Home never prompts for packs, and every mode plays from built-in and streamed songs.
- **Ads:** added the captions shown under the fake ad (`ad.rewardCaption`, `ad.interstitialCaption`).
- **Update:** says "new songs", not "new packs"; the secondary button is "Play offline songs".

## App and first launch

| Key | English | Amharic |
|---|---|---|
| `app.name` | Yeman Zefen | የማን ዘፈን |
| `app.tagline` | Whose song is it? | የማን ዘፈን ነው? |
| `onboard.lang.title` | Choose your language | ቋንቋ ይምረጡ |
| `onboard.lang.amharic` | አማርኛ | አማርኛ |
| `onboard.lang.english` | English | English |
| `onboard.lang.later` | You can change this anytime in Settings. | ይህን በማንኛውም ጊዜ በቅንብሮች ውስጥ መቀየር ይችላሉ። |
| `onboard.welcome.title` | Name the song from its first notes. | ዘፈኑን ከመጀመሪያዎቹ ድምፆች ይለዩ። |
| `onboard.welcome.body` | Hear a short clip, then pick the song or the singer. No sign-up needed. | አጭር ቅንጭብ ያዳምጡ፣ ከዚያ ዘፈኑን ወይም ዘፋኙን ይምረጡ። መመዝገብ አያስፈልግም። |
| `onboard.welcome.start` | Start playing | መጫወት ይጀምሩ |
| `common.next` | Next | ቀጣይ |

## Home

| Key | English | Amharic |
|---|---|---|
| `home.hello` | Ready for a song? | ለዘፈን ዝግጁ ነዎት? |
| `home.quickPlay` | Play | ይጫወቱ |
| `home.quickPlay.label` | Play button starts | ይጫወቱ የሚጀምረው |
| `home.quickPlay.settings` | {era} · {mode} · {difficulty} | {era} · {mode} · {difficulty} |
| `home.chooseMode` | More ways to play | ሌሎች የአጨዋወት መንገዶች |
| `home.mode.intro.short` | The opening of the song | የዘፈኑ መጀመሪያ |
| `home.mode.middle.short` | Harder · +25% points | ይከብዳል · +25% ነጥብ |
| `home.mode.era.short` | Name the generation | ዘመኑን ይለዩ |
| `home.leaderboard` | Leaderboard | የደረጃ ሰንጠረዥ |
| `home.leaderboard.guest` | Sign in to get a rank | ደረጃ ለማግኘት ይግቡ |
| `home.leaderboard.offline` | Needs internet | ኢንተርኔት ያስፈልጋል |
| `home.best.label` | Your best | ምርጥ ውጤትዎ |
| `home.best.none` | Play a game to set your first best score. | የመጀመሪያ ምርጥ ውጤትዎን ለማስመዝገብ አንድ ጨዋታ ይጫወቱ። |
| `home.builtIn` | Built-in songs | አብረው የመጡ ዘፈኖች |
| `home.quickPlay.mode.intro` | Intro | መግቢያ |
| `home.quickPlay.mode.middle` | Middle | ከመሀል |
| `home.quickPlay.mode.era` | Which Era? | የየትኛው ዘመን? |
| `difficulty.easy.short` | Easy | ቀላል |
| `difficulty.medium.short` | Medium | መካከለኛ |
| `difficulty.hard.short` | Hard | ከባድ |
| `nav.home` | Home | መነሻ |
| `nav.play` | Play | ይጫወቱ |
| `nav.settings` | Settings | ቅንብሮች |
| `nav.back` | Back | ይመለሱ |

> **Short labels for the Play line** (added in Phase 2 · Sprint 2). The Home boards show "The '80s · Intro · Easy" and "የ80ዎቹ · መግቢያ · ቀላል", but the deck only had the long names ("Guess the Intro", "Easy · 10 s"). The six `home.quickPlay.mode.*` and `difficulty.*.short` rows are those short forms. **Reviewed by a native speaker**, as is the changed `feedback.revealEra` (the era names already start with የ, so it no longer adds one).

## Mode select

| Key | English | Amharic |
|---|---|---|
| `mode.title` | How do you want to play? | እንዴት መጫወት ይፈልጋሉ? |
| `mode.intro.name` | Guess the Intro | መግቢያውን ይገምቱ |
| `mode.intro.desc` | The opening of the song. The classic. | የዘፈኑ መጀመሪያ። የተለመደው ጨዋታ። |
| `mode.middle.name` | Guess from the Middle | ከመሀል ይገምቱ |
| `mode.middle.desc` | A clip from the middle. Harder, so it's worth more. | ከዘፈኑ መሀል የተወሰደ ቅንጭብ። ስለሚከብድ ተጨማሪ ነጥብ ያስገኛል። |
| `mode.middle.tag` | +25% | +25% |
| `mode.era.name` | Which Era? | የየትኛው ዘመን? |
| `mode.era.desc` | Hear a song and name its generation. | ዘፈኑን ሰምተው ዘመኑን ይለዩ። |
| `mode.bonus` | Bonus | ተጨማሪ |
| `mode.guess.label` | Guess the | የሚገምቱት |
| `mode.guess.song` | Song | ዘፈኑን |
| `mode.guess.artist` | Artist | ዘፋኙን |

## Era, genre and difficulty

> **Catalog names.** Eras and genres are also stored in the database (`generations` and `genres`, admin-editable), which is what the app shows once it reads names from the catalog. The two agree: genres use the database's Amharic spellings, and migration `0005_era_display_names` renamed the English eras to "The '80s", "The '90s" and "The 2000s".

| Key | English | Amharic |
|---|---|---|
| `era.title` | Pick an era | ዘመን ይምረጡ |
| `era.all` | All eras | ሁሉም ዘመኖች |
| `era.golden` | Golden Age | ወርቃማው ዘመን |
| `era.golden.range` | Before 1980 | ከ1980 በፊት |
| `era.80s` | The '80s | የ80ዎቹ |
| `era.90s` | The '90s | የ90ዎቹ |
| `era.2000s` | The 2000s | የ2000ዎቹ |
| `era.modern` | Modern | ዘመናዊ |
| `era.modern.range` | 2010 and later | ከ2010 ወዲህ |
| `era.offlineUnavailable` | Needs internet or a downloaded pack | ኢንተርኔት ወይም የወረደ ጥቅል ያስፈልጋል |
| `genre.title` | Genre (optional) | ዘውግ (አማራጭ) |
| `genre.any` | Any genre | ማንኛውም ዘውግ |
| `genre.tizita` | Tizita | ትዝታ |
| `genre.ethiojazz` | Ethio-jazz | ኢትዮ ጃዝ |
| `genre.traditional` | Traditional | ባሕላዊ |
| `genre.pop` | Pop | ፖፕ |
| `genre.hiphop` | Hip-hop | ሂፕ ሆፕ |
| `difficulty.title` | Clip length | የቅንጭቡ ርዝመት |
| `difficulty.easy` | Easy · 10 s | ቀላል · 10 ሰከንድ |
| `difficulty.medium` | Medium · 5 s | መካከለኛ · 5 ሰከንድ |
| `difficulty.hard` | Hard · 3 s | ከባድ · 3 ሰከንድ |
| `setup.start` | Start · {total} rounds | ይጀምሩ · {total} ዙሮች |
| `setup.tooFewSongs` | Not enough songs for this choice yet. Try "All eras" or another genre. | ለዚህ ምርጫ ገና በቂ ዘፈኖች የሉም። "ሁሉም ዘመኖች"ን ወይም ሌላ ዘውግ ይሞክሩ። |

## Round

| Key | English | Amharic |
|---|---|---|
| `round.counter` | {n} / {total} | {n} / {total} |
| `round.score` | {points} pts | {points} ነጥብ |
| `round.loading` | Getting the next song… | ቀጣዩን ዘፈን በማዘጋጀት ላይ… |
| `round.loading.note` | If it doesn't load in 10 seconds, we'll skip this round. You won't lose points. | በ10 ሰከንድ ውስጥ ካልተጫነ ይህን ዙር እንዘልለዋለን። ነጥብ አይቀነስብዎትም። |
| `round.listen` | Listen… | ያዳምጡ… |
| `round.question.song` | Which song is this? | ይህ የትኛው ዘፈን ነው? |
| `round.question.artist` | Who sings this? | ይህን ዘፈን የዘፈነው ማን ነው? |
| `round.question.era` | Which era is this song from? | ይህ ዘፈን የየትኛው ዘመን ነው? |
| `round.secondsLeft` | {s} s | {s} ሰከንድ |
| `round.hint` | Hint: remove 2 answers | ፍንጭ፦ 2 መልሶችን ያስወግዱ |
| `round.hint.terms` | Watch a short ad. This round's points are halved. | አጭር ማስታወቂያ ይመልከቱ። የዚህ ዙር ነጥብ በግማሽ ይቀንሳል። |
| `round.hint.paused` | The timer pauses for up to 8 seconds while you decide, and while the ad plays. | ለመወሰን እስከ 8 ሰከንድ፣ እንዲሁም ማስታወቂያው እስኪያልቅ ድረስ ሰዓቱ ይቆማል። |
| `round.hint.closesIn` | {s} s | {s} ሰከንድ |
| `round.timerPaused` | Paused | ቆሟል |
| `round.hint.watch` | Watch ad | ማስታወቂያ ይመልከቱ |
| `round.hint.cancel` | No thanks | አይ፣ ይቅር |
| `round.hint.button` | Hint | ፍንጭ |
| `round.leave` | Leave game | ከጨዋታው ይውጡ |
| `round.leave.title` | Leave this game? | ጨዋታውን ያቋርጣሉ? |
| `round.leave.body` | Your score for this game won't be saved. | የዚህ ጨዋታ ውጤት አይቀመጥም። |
| `round.leave.confirm` | Leave | ይውጡ |
| `round.leave.cancel` | Keep playing | መጫወት ይቀጥሉ |
| `a11y.answer` | Answer {n}: {text} | መልስ {n}፦ {text} |
| `a11y.timer` | {s} seconds left | {s} ሰከንድ ቀርቷል |
| `a11y.playing` | Clip playing | ቅንጭቡ እየተጫወተ ነው |

## Answer feedback

| Key | English | Amharic |
|---|---|---|
| `feedback.correct` | Correct | ትክክል |
| `feedback.points` | +{points} | +{points} |
| `feedback.speedBonus` | Speed bonus +{bonus} | የፍጥነት ጉርሻ +{bonus} |
| `feedback.wrong` | Not this one | ይህ አይደለም |
| `feedback.reveal` | It was {song} · {artist} | መልሱ፦ {song} · {artist} |
| `feedback.tapToContinue` | Tap to continue · {s} s | ለመቀጠል ይንኩ · {s} ሰከንድ |
| `feedback.yourPick` | Your pick | የእርስዎ ምርጫ |
| `feedback.revealEra` | It's from {era} | {era} ዘፈን ነው |
| `feedback.timeout` | Time's up | ጊዜው አልቋል |
| `feedback.hintUsed` | Hint used · half points | ፍንጭ ተጠቅመዋል · ግማሽ ነጥብ |
| `feedback.skipped` | We skipped a song that wouldn't load or play. No points lost. | ሊጫን ወይም ሊጫወት ያልቻለ ዘፈን ዘለልን። ነጥብ አልተቀነሰም። |

## Results

| Key | English | Amharic |
|---|---|---|
| `results.title` | Game complete | ጨዋታው ተጠናቋል |
| `results.score` | {score} points | {score} ነጥብ |
| `results.correctCount` | {correct} of {total} right | ከ{total} {correct} ትክክል |
| `results.newBest` | New personal best | አዲስ የግል ምርጥ ውጤት |
| `results.rounds` | Your rounds | የእርስዎ ዙሮች |
| `results.playAgain` | Play again | እንደገና ይጫወቱ |
| `results.change` | Change era or mode | ዘመን ወይም ጨዋታ ይቀይሩ |
| `results.home` | Home | መነሻ |
| `results.guestRank` | Sign in to put this score on the leaderboard | ይህ ውጤት በደረጃ ሰንጠረዡ ላይ እንዲሰፍር ይግቡ |
| `results.weeklyRank` | You're #{rank} this week | በዚህ ሳምንት {rank}ኛ ነዎት |
| `results.savedOffline` | Score saved. It will be sent when you're back online. | ውጤቱ ተቀምጧል። ኢንተርኔት ሲገኝ ይላካል። |
| `results.notRanked` | This game couldn't be checked, so it won't count toward rankings. | ይህ ጨዋታ ሊረጋገጥ ስላልቻለ ለደረጃ አይቆጠርም። |

## Leaderboard

| Key | English | Amharic |
|---|---|---|
| `lb.title` | Leaderboard | የደረጃ ሰንጠረዥ |
| `lb.weekly` | This week | የዚህ ሳምንት |
| `lb.allTime` | All time | የምንጊዜም |
| `lb.era` | Era: {era} | ዘመን፦ {era} |
| `lb.you` | You | እርስዎ |
| `lb.yourRank` | Your rank: #{rank} | ደረጃዎ፦ {rank}ኛ |
| `lb.points` | {points} pts | {points} ነጥብ |
| `lb.notRanked` | Finish a game this week to get a rank. | ደረጃ ለማግኘት በዚህ ሳምንት አንድ ጨዋታ ያጠናቁ። |
| `lb.guest.title` | Want your name up here? | ስምዎ እዚህ እንዲሰፍር ይፈልጋሉ? |
| `lb.guest.body` | Sign in to rank. Your scores come with you. | ደረጃ ለማግኘት ይግቡ። ውጤትዎ አይጠፋም። |
| `lb.guest.cta` | Sign in | ይግቡ |
| `lb.empty` | No scores yet this week. Be the first. | በዚህ ሳምንት እስካሁን ውጤት የለም። የመጀመሪያው ይሁኑ። |
| `lb.offline` | You're offline. Showing the board from {time}. | ከኢንተርኔት ውጭ ነዎት። የ{time} ሰንጠረዥ እየታየ ነው። |
| `lb.offline.none` | Connect to the internet to see the leaderboard. | የደረጃ ሰንጠረዡን ለማየት ከኢንተርኔት ጋር ይገናኙ። |
| `lb.loading` | Loading the leaderboard… | የደረጃ ሰንጠረዡን በመጫን ላይ… |

## Settings › Offline play

| Key | English | Amharic |
|---|---|---|
| `packs.title` | Offline play | ያለ ኢንተርኔት መጫወት |
| `packs.intro` | Online, songs load as you play. Download packs to play without internet. | ኢንተርኔት ሲኖር ዘፈኖች በሚጫወቱበት ጊዜ ይጫናሉ። ያለ ኢንተርኔት ለመጫወት ጥቅሎችን ያውርዱ። |
| `packs.wifiOnly` | Download packs on Wi-Fi only | ጥቅሎችን በዋይፋይ ብቻ ያውርዱ |
| `packs.mobilePrefetch` | Download upcoming songs on mobile data | ቀጣይ ዘፈኖችን በሞባይል ዳታ ያውርዱ |
| `packs.mobilePrefetch.help` | Off saves data: only songs already on your phone play. | ሲጠፋ ዳታ ይቆጥባል፤ በስልክዎ ላይ ያሉ ዘፈኖች ብቻ ይጫወታሉ። |
| `packs.cacheOfCap` | Cache {size} of {cap} MB | ማቆያ {size} ከ{cap} ሜባ |
| `packs.storageUsed` | Songs use {total} MB here: built-in {builtIn} MB, packs {packs} MB, cache {cache} MB. | ዘፈኖቹ እዚህ {total} ሜባ ይይዛሉ፦ አብረው የመጡ {builtIn} ሜባ፣ ጥቅሎች {packs} ሜባ፣ ማቆያ {cache} ሜባ። |
| `packs.clearCache` | Clear cache | ማቆያውን ያጽዱ |
| `packs.builtIn` | Built-in songs | አብረው የመጡ ዘፈኖች |
| `packs.builtIn.meta` | {count} songs · comes with the app | {count} ዘፈኖች · ከመተግበሪያው ጋር |
| `packs.always` | Always there | ሁልጊዜ አለ |
| `packs.onPhone` | On this phone | በዚህ ስልክ ላይ |
| `packs.available` | Available to download | ለማውረድ የሚገኙ |
| `packs.songs` | {count} songs | {count} ዘፈኖች |
| `packs.size` | {size} MB | {size} ሜባ |
| `packs.download` | Download | ያውርዱ |
| `packs.progress` | {percent}% | {percent}% |
| `packs.cancel` | Cancel | ይሰርዙ |
| `packs.verifying` | Checking files… | ፋይሎችን በማረጋገጥ ላይ… |
| `packs.downloaded` | Downloaded | ወርዷል |
| `packs.updateAvailable` | Update available | ማሻሻያ አለ |
| `packs.update` | Update · {size} MB | ያዘምኑ · {size} ሜባ |
| `packs.remove` | Remove | ያስወግዱ |
| `packs.remove.confirm` | Remove {name}? You can download it again later. | {name} ይወገድ? በኋላ እንደገና ማውረድ ይችላሉ። |
| `packs.mobileData.title` | Download on mobile data? | በሞባይል ዳታ ይውረድ? |
| `packs.mobileData.body` | This pack is {size} MB. | ይህ ጥቅል {size} ሜባ ነው። |
| `packs.mobileData.confirm` | Download now | አሁን ያውርዱ |
| `packs.mobileData.wait` | Wait for Wi-Fi | ዋይፋይ ይጠብቁ |
| `packs.storageFull` | Not enough space. Free up {size} MB and try again. | በቂ ቦታ የለም። {size} ሜባ ነፃ አድርገው እንደገና ይሞክሩ። |
| `packs.offline` | Connect to the internet to download packs. | ጥቅሎችን ለማውረድ ከኢንተርኔት ጋር ይገናኙ። |

> **Storage line** (added in Phase 4 · Sprint 1). Offline play now shows the cache with its cap (`packs.cacheOfCap`, which replaces `packs.cache`) and what the songs take by source (`packs.storageUsed`). **Amharic not yet reviewed:** both are marked `REVIEW` in `app_am.arb`.

## Sign in and register

| Key | English | Amharic |
|---|---|---|
| `auth.prompt.title` | Keep your scores | ውጤቶችዎን ያስቀምጡ |
| `auth.prompt.body` | Sign in to keep your progress on any phone and join the global leaderboard. | እድገትዎን በማንኛውም ስልክ ለማቆየትና በዓለም አቀፉ የደረጃ ሰንጠረዥ ለመሳተፍ ይግቡ። |
| `auth.prompt.carryOver` | Your scores so far come with you. | እስካሁን ያገኙት ውጤት አይጠፋም። |
| `auth.google` | Continue with Google | በGoogle ይቀጥሉ |
| `auth.apple` | Continue with Apple | በApple ይቀጥሉ |
| `auth.email` | Continue with email | በኢሜይል ይቀጥሉ |
| `auth.notNow` | Not now | አሁን አይደለም |
| `auth.email.label` | Email | ኢሜይል |
| `auth.password.label` | Password | የይለፍ ቃል |
| `auth.email.submit` | Sign in | ይግቡ |
| `auth.email.create` | New here? Create an account | አዲስ ነዎት? መለያ ይፍጠሩ |
| `auth.email.forgot` | Forgot password? | የይለፍ ቃልዎን ረስተዋል? |
| `auth.signingIn` | Signing in… | በመግባት ላይ… |
| `auth.signedIn` | Signed in as {name} | እንደ {name} ገብተዋል |
| `auth.linkFailed` | We couldn't link your account. Your scores are safe on this phone, and we'll try again. | መለያዎን ማገናኘት አልተቻለም። ውጤቶችዎ በዚህ ስልክ ላይ ደህና ናቸው፤ እንደገና እንሞክራለን። |
| `auth.error.email` | Check your email address. | የኢሜይል አድራሻዎን ያረጋግጡ። |
| `auth.error.password` | Wrong email or password. | ኢሜይሉ ወይም የይለፍ ቃሉ ትክክል አይደለም። |
| `auth.name.title` | Pick a display name | የሚታይ ስም ይምረጡ |
| `auth.name.body` | This is the name other players see on the leaderboard. | ይህ በደረጃ ሰንጠረዡ ላይ ሌሎች ተጫዋቾች የሚያዩት ስም ነው። |
| `auth.name.label` | Display name | የሚታይ ስም |
| `auth.name.save` | Save name | ስሙን ያስቀምጡ |
| `auth.name.error.short` | Use at least 2 characters. | ቢያንስ 2 ፊደላት ይጠቀሙ። |
| `auth.name.error.taken` | That name is taken. Try another. | ይህ ስም ተይዟል። ሌላ ይሞክሩ። |

> **Display-name step** (added in Phase 2 · Sprint 2). Step 4 had no screen for choosing the name that shows on the leaderboard, so the six `auth.name.*` rows are new. **Reviewed by a native speaker.**

## Settings

| Key | English | Amharic |
|---|---|---|
| `settings.title` | Settings | ቅንብሮች |
| `settings.language` | Language | ቋንቋ |
| `settings.sound` | Sound effects | የድምፅ ውጤቶች |
| `settings.haptics` | Vibration | ንዝረት |
| `settings.account` | Account | መለያ |
| `settings.guest` | Playing as a guest | በእንግድነት እየተጫወቱ ነው |
| `settings.signIn` | Sign in | ይግቡ |
| `settings.signOut` | Sign out | ይውጡ |
| `settings.signOut.confirm` | Sign out? Your scores stay saved to your account. | ይወጣሉ? ውጤቶችዎ በመለያዎ ላይ ተቀምጠው ይቆያሉ። |
| `settings.delete` | Delete account | መለያ ይሰርዙ |
| `settings.delete.body` | This permanently deletes your account and your leaderboard scores. It can't be undone. | ይህ መለያዎንና የደረጃ ውጤቶችዎን እስከመጨረሻው ይሰርዛል። መመለስ አይቻልም። |
| `settings.delete.confirm` | Delete my account | መለያዬን ይሰርዙ |
| `settings.adPrivacy` | Ad privacy choices | የማስታወቂያ ግላዊነት ምርጫዎች |
| `settings.offline` | Offline play · {count, plural, =1{1 pack} other{{count} packs}} · {size} MB | ያለ ኢንተርኔት መጫወት · {count, plural, =1{1 ጥቅል} other{{count} ጥቅሎች}} · {size} ሜባ |
| `settings.privacy` | Privacy policy | የግላዊነት ፖሊሲ |
| `settings.about` | About and licenses | ስለ መተግበሪያው እና ፈቃዶች |
| `settings.version` | Version {version} | ስሪት {version} |
| `settings.musicCredit` | Music used under license from [ASSOCIATION NAME]. | ሙዚቃዎቹ ጥቅም ላይ የዋሉት በ[የማህበሩ ስም] ፈቃድ ነው። |

## Ads and consent

| Key | English | Amharic |
|---|---|---|
| `consent.title` | Ads keep this game free | ጨዋታው ነፃ የሆነው በማስታወቂያ ነው |
| `consent.body` | Next, you'll choose how ads may use your data. You can change this anytime in Settings. | በመቀጠል ማስታወቂያዎች መረጃዎን እንዴት እንደሚጠቀሙ ይመርጣሉ። ይህን በማንኛውም ጊዜ በቅንብሮች ውስጥ መቀየር ይችላሉ። |
| `consent.continue` | Continue | ይቀጥሉ |
| `ad.label` | Ad | ማስታወቂያ |
| `ad.loading` | Loading ad… | ማስታወቂያ በመጫን ላይ… |
| `ad.unavailable` | No ad is available right now. Try again later. | አሁን ማስታወቂያ የለም። ቆይተው እንደገና ይሞክሩ። |
| `ad.notFinished` | Watch the whole ad to get the hint. | ፍንጩን ለማግኘት ማስታወቂያውን እስከመጨረሻው ይመልከቱ። |
| `ad.rewardCaption` | Your hint is on its way… | ፍንጭዎ እየመጣ ነው… |
| `ad.interstitialCaption` | Ads keep this game free | ጨዋታው ነፃ የሆነው በማስታወቂያ ነው |

## Update, offline and out-of-songs states

| Key | English | Amharic |
|---|---|---|
| `update.title` | Time to update | ማዘመን ያስፈልጋል |
| `update.body` | This version can't connect to the game server anymore. Update to use the leaderboard and get new songs. | ይህ ስሪት ከጨዋታው አገልጋይ ጋር መገናኘት አይችልም። የደረጃ ሰንጠረዡን ለመጠቀምና አዲስ ዘፈኖችን ለማግኘት ያዘምኑ። |
| `update.cta.android` | Update on Google Play | በGoogle Play ያዘምኑ |
| `update.cta.ios` | Update on the App Store | በApp Store ያዘምኑ |
| `update.playOffline` | Play offline songs | ያለ ኢንተርኔት ዘፈኖች ይጫወቱ |
| `offline.banner` | You're offline. You can still play built-in and downloaded songs. | ከኢንተርኔት ውጭ ነዎት። አብረው የመጡትንና የወረዱትን ዘፈኖች መጫወት ይችላሉ። |
| `offline.banner.builtInOnly` | You're offline. You can still play the {count} built-in songs. | ከኢንተርኔት ውጭ ነዎት። አብረው የመጡትን {count} ዘፈኖች መጫወት ይችላሉ። |
| `offline.banner.short` | You're offline. | ከኢንተርኔት ውጭ ነዎት። |
| `offline.pending` | {count} games waiting to be sent | {count} ጨዋታዎች ለመላክ እየጠበቁ ነው |
| `offline.synced` | Back online. Your scores have been sent. | ኢንተርኔት ተመልሷል። ውጤቶችዎ ተልከዋል። |
| `empty.outOfSongs.title` | You've played every song here | እዚህ ያሉትን ዘፈኖች በሙሉ ተጫውተዋል |
| `empty.outOfSongs.body` | You're offline, and you've heard all the songs on this phone recently. Download a pack in Settings › Offline play for more. | ከኢንተርኔት ውጭ ነዎት፤ በዚህ ስልክ ላይ ያሉትን ዘፈኖች በሙሉ በቅርቡ ሰምተዋል። ለተጨማሪ ዘፈኖች በቅንብሮች › ያለ ኢንተርኔት መጫወት ውስጥ ጥቅል ያውርዱ። |
| `empty.outOfSongs.packs` | Browse packs | ጥቅሎችን ይመልከቱ |
| `empty.outOfSongs.replay` | Play them again | ዘፈኖቹን እንደገና ይጫወቱ |

## Errors and loading

| Key | English | Amharic |
|---|---|---|
| `error.generic.title` | Something went wrong | የሆነ ችግር ተፈጥሯል |
| `error.generic.body` | Please try again. If it keeps happening, restart the app. | እባክዎ እንደገና ይሞክሩ። ችግሩ ከቀጠለ መተግበሪያውን ዘግተው ይክፈቱ። |
| `error.retry` | Try again | እንደገና ይሞክሩ |
| `error.download` | Download failed. Check your connection and try again. | ማውረዱ አልተሳካም። ግንኙነትዎን አረጋግጠው እንደገና ይሞክሩ። |
| `error.packCorrupt` | Part of this pack didn't download correctly. Downloading it again… | የጥቅሉ የተወሰነ ክፍል በትክክል አልወረደም። እንደገና በማውረድ ላይ… |
| `error.sync` | Couldn't send your scores. We'll try again automatically. | ውጤቶችዎን መላክ አልተቻለም። በራሱ እንደገና ይሞክራል። |
| `loading.app` | Tuning up… | በመዘጋጀት ላይ… |
| `loading.generic` | Loading… | በመጫን ላይ… |
