import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_context.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/widgets.dart';
import '../l10n/app_localizations.dart';

/// A dev-only page showing every component in every state, in English or
/// Amharic and at text scale 1.0 or 1.3. Run it with `flutter run -t lib/main_gallery.dart`.
/// It is how a design change is checked against `docs/design/screens/` without
/// building the screens.
class ComponentGalleryApp extends StatefulWidget {
  const ComponentGalleryApp({
    super.key,
    this.initialLocale = const Locale('en'),
    this.initialTextScale = 1.0,
  });

  final Locale initialLocale;
  final double initialTextScale;

  @override
  State<ComponentGalleryApp> createState() => _ComponentGalleryAppState();
}

class _ComponentGalleryAppState extends State<ComponentGalleryApp> {
  late Locale _locale = widget.initialLocale;
  late double _scale = widget.initialTextScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Component gallery',
      locale: _locale,
      theme: buildAppTheme(_locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_scale)),
        child: child!,
      ),
      home: ComponentGallery(
        locale: _locale,
        textScale: _scale,
        onLocale: (l) => setState(() => _locale = l),
        onTextScale: (s) => setState(() => _scale = s),
      ),
    );
  }
}

/// The gallery body. Strings come from `docs/design/copy.md` (keys in the comments).
class ComponentGallery extends StatelessWidget {
  const ComponentGallery({
    super.key,
    required this.locale,
    required this.textScale,
    required this.onLocale,
    required this.onTextScale,
  });

  final Locale locale;
  final double textScale;
  final ValueChanged<Locale> onLocale;
  final ValueChanged<double> onTextScale;

  bool get _am => locale.languageCode == 'am';
  String _t(String en, String am) => _am ? am : en;

  void _noop() {}

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: SpacingTokens.n24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: text.label.copyWith(color: ColorTokens.textSecondary),
          ),
          const SizedBox(height: SpacingTokens.n10),
          for (final c in children) ...[
            c,
            const SizedBox(height: SpacingTokens.n12),
          ],
        ],
      ),
    );

    final artists = [
      _t('Mahmoud Ahmed', 'ማሕሙድ አሕመድ'),
      _t('Tilahun Gessesse', 'ጥላሁን ገሠሠ'),
      _t('Aster Aweke', 'አስቴር አወቀ'),
      _t('Muluken Melesse', 'ሙሉቀን መለሰ'),
    ];
    final correct = _t('Correct', 'ትክክል'); // feedback.correct
    final yourPick = _t('Your pick', 'የእርስዎ ምርጫ'); // feedback.yourPick

    Widget grid(List<Widget> tiles) => EqualHeightGrid(children: tiles);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Component gallery'),
        actions: [
          IconButton(
            tooltip: textScale == 1.0 ? 'Text scale 1.3' : 'Text scale 1.0',
            icon: Text(textScale == 1.0 ? '1.0×' : '1.3×', style: text.label),
            onPressed: () =>
                onTextScale(textScale == 1.0 ? TypeTokens.textScaleMax : 1.0),
          ),
          TextButton(
            onPressed: () => onLocale(Locale(_am ? 'en' : 'am')),
            child: Text(_am ? 'English' : 'አማርኛ'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SpacingTokens.n16,
          0,
          SpacingTokens.n16,
          SpacingTokens.n32,
        ),
        children: [
          section('Buttons', [
            PrimaryButton(
              label: _t('Start · 10 rounds', 'ይጀምሩ · 10 ዙሮች'),
              onPressed: _noop,
            ), // setup.start
            PrimaryButton(
              label: _t('Play', 'ይጫወቱ'),
              icon: Icons.play_arrow_rounded,
              expand: false,
              onPressed: _noop,
            ), // nav.play
            Row(
              children: [
                PrimaryButton(
                  label: _t('Download', 'ያውርዱ'),
                  small: true,
                  onPressed: _noop,
                ), // packs.download
                const SizedBox(width: SpacingTokens.n12),
                PrimaryButton(
                  label: _t('Download', 'ያውርዱ'),
                  small: true,
                  onPressed: null,
                ),
              ],
            ),
            PrimaryButton(
              label: _t('Start · 10 rounds', 'ይጀምሩ · 10 ዙሮች'),
              onPressed: null,
            ),
            SecondaryButton(
              label: _t('Change era or mode', 'ዘመን ወይም ጨዋታ ይቀይሩ'),
              onPressed: _noop,
            ), // results.change
            Row(
              children: [
                AppIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  semanticLabel: _t('Back', 'ይመለሱ'),
                  onPressed: _noop,
                ), // nav.back
                const SizedBox(width: SpacingTokens.n12),
                AppIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: _t('Cancel', 'ይሰርዙ'),
                  onPressed: null,
                ), // packs.cancel
              ],
            ),
          ]),
          section('Answer tiles: idle', [
            grid([
              for (var i = 0; i < 4; i++)
                AnswerTile(text: artists[i], onTap: _noop),
            ]),
          ]),
          section(
            'Answer tiles: selected · correct · wrong · disabled · removed',
            [
              grid([
                AnswerTile(text: artists[0], state: AnswerState.selected),
                AnswerTile(
                  text: artists[0],
                  state: AnswerState.correct,
                  stateLabel: correct,
                ),
                AnswerTile(
                  text: artists[1],
                  state: AnswerState.wrong,
                  stateLabel: yourPick,
                ),
                AnswerTile(text: artists[2], state: AnswerState.disabled),
                AnswerTile(text: artists[3], state: AnswerState.removed),
              ]),
            ],
          ),
          section('Timer bar · paused · no pill', [
            TimerBar(
              fraction: 0.73,
              label: _t('7 s', '7 ሰከንድ'),
            ), // round.secondsLeft
            TimerBar(
              fraction: 0.47,
              label: _t('Paused', 'ቆሟል'),
            ), // round.timerPaused
            const TimerBar(fraction: 1),
          ]),
          section('Playing indicator · playing, then stopped', [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: SpacingTokens.n16,
              runSpacing: SpacingTokens.n16,
              children: [
                PlayingIndicator(
                  playing: true,
                  semanticLabel: _t('Clip playing', 'ቅንጭቡ እየተጫወተ ነው'),
                ), // a11y.playing
                const PlayingIndicator(playing: false),
              ],
            ),
          ]),
          section('Era chips', [
            Wrap(
              spacing: SpacingTokens.n8,
              runSpacing: SpacingTokens.n8,
              children: [
                EraChip(label: _t('All eras', 'ሁሉም ዘመኖች'), generationId: 0),
                EraChip(label: _t('Golden Age', 'ወርቃማው ዘመን'), generationId: 1),
                EraChip(label: _t("The '80s", 'የ80ዎቹ'), generationId: 2),
                EraChip(label: _t("The '90s", 'የ90ዎቹ'), generationId: 3),
                EraChip(label: _t('The 2000s', 'የ2000ዎቹ'), generationId: 4),
                EraChip(label: _t('Modern', 'ዘመናዊ'), generationId: 5),
              ],
            ),
          ]),
          section('Era cards: selected · unavailable', [
            grid([
              EraCard(
                label: _t('All eras', 'ሁሉም ዘመኖች'),
                generationId: 0,
                selected: false,
                onTap: _noop,
              ),
              EraCard(
                label: _t('Golden Age', 'ወርቃማው ዘመን'),
                subtitle: _t('Before 1980', 'ከ1980 በፊት'),
                generationId: 1,
                selected: false,
                onTap: _noop,
              ),
              EraCard(
                label: _t("The '80s", 'የ80ዎቹ'),
                generationId: 2,
                selected: true,
                onTap: _noop,
              ),
              EraCard(
                label: _t("The '90s", 'የ90ዎቹ'),
                generationId: 3,
                selected: false,
                onTap: _noop,
              ),
              EraCard(
                label: _t('The 2000s', 'የ2000ዎቹ'),
                generationId: 4,
                selected: false,
                enabled: false,
                onTap: null,
              ),
              EraCard(
                label: _t('Modern', 'ዘመናዊ'),
                subtitle: _t('2010 and later', 'ከ2010 ወዲህ'),
                generationId: 5,
                selected: false,
                onTap: _noop,
              ),
            ]),
          ]),
          section('Pack cards', [
            PackCard(
              name: _t('Built-in songs', 'አብረው የመጡ ዘፈኖች'), // packs.builtIn
              meta: _t(
                '25 songs · comes with the app',
                '25 ዘፈኖች · ከመተግበሪያው ጋር',
              ), // packs.builtIn.meta
              status: PackStatus.builtIn,
              statusLabel: _t('Always there', 'ሁልጊዜ አለ'), // packs.always
            ),
            PackCard(
              name: _t("The '80s", 'የ80ዎቹ'),
              meta: _t('40 songs · 12 MB', '40 ዘፈኖች · 12 ሜባ'),
              generationId: 2,
              status: PackStatus.installed,
              statusLabel: _t('Downloaded', 'ወርዷል'), // packs.downloaded
            ),
            PackCard(
              name: _t('Golden Age', 'ወርቃማው ዘመን'),
              meta: _t('42% · 60 songs · 18 MB', '42% · 60 ዘፈኖች · 18 ሜባ'),
              generationId: 1,
              status: PackStatus.downloading,
              progress: 0.42,
              cancelLabel: _t('Cancel', 'ይሰርዙ'),
              onCancel: _noop,
            ),
            PackCard(
              name: _t("The '90s", 'የ90ዎቹ'),
              meta: _t('45 songs · 14 MB', '45 ዘፈኖች · 14 ሜባ'),
              generationId: 3,
              status: PackStatus.verifying,
              statusLabel: _t(
                'Checking files…',
                'ፋይሎችን በማረጋገጥ ላይ…',
              ), // packs.verifying
            ),
            PackCard(
              name: _t('The 2000s', 'የ2000ዎቹ'),
              meta: _t('50 songs · 15 MB', '50 ዘፈኖች · 15 ሜባ'),
              generationId: 4,
              status: PackStatus.updateAvailable,
              statusLabel: _t(
                'Update available',
                'ማሻሻያ አለ',
              ), // packs.updateAvailable
              actionLabel: _t('Update · 3 MB', 'ያዘምኑ · 3 ሜባ'), // packs.update
              onAction: _noop,
            ),
            PackCard(
              name: _t('Modern', 'ዘመናዊ'),
              meta: _t('30 songs · 9 MB', '30 ዘፈኖች · 9 ሜባ'),
              generationId: 5,
              status: PackStatus.notInstalled,
              actionLabel: _t('Download', 'ያውርዱ'),
              onAction: _noop,
            ),
            PackCard(
              name: _t('Golden Age', 'ወርቃማው ዘመን'),
              meta: _t('60 songs · 18 MB', '60 ዘፈኖች · 18 ሜባ'),
              generationId: 1,
              status: PackStatus.failed,
              errorMessage: _t(
                'Download failed. Check your connection and try again.',
                'ማውረዱ አልተሳካም። ግንኙነትዎን አረጋግጠው እንደገና ይሞክሩ።',
              ), // error.download
              retryLabel: _t('Try again', 'እንደገና ይሞክሩ'), // error.retry
              onRetry: _noop,
            ),
          ]),
          section('Score badges', [
            Wrap(
              spacing: SpacingTokens.n8,
              runSpacing: SpacingTokens.n8,
              children: [
                ScoreBadge(label: _t('563 pts', '563 ነጥብ')), // round.score
                ScoreBadge.best(
                  label: _t('New personal best', 'አዲስ የግል ምርጥ ውጤት'),
                ), // results.newBest
              ],
            ),
          ]),
          section('List rows', [
            ListRow(
              title: _t('Guess the Intro', 'መግቢያውን ይገምቱ'),
              subtitle: _t('The opening of the song', 'የዘፈኑ መጀመሪያ'),
              icon: Icons.music_note_rounded,
              onTap: _noop,
            ),
            ListRow(
              title: _t('Which Era?', 'የየትኛው ዘመን?'),
              subtitle: _t('Name the generation', 'ዘመኑን ይለዩ'),
              icon: Icons.schedule_rounded,
              iconColor: ColorTokens.paletteSage,
              onTap: _noop,
            ),
            ListRow(
              dark: true,
              title: _t('Leaderboard', 'የደረጃ ሰንጠረዥ'),
              subtitle: _t('Sign in to get a rank', 'ደረጃ ለማግኘት ይግቡ'),
              icon: Icons.emoji_events_outlined,
              onTap: _noop,
            ),
          ]),
          section('Switch · on, off, disabled', [
            SettingsGroup(
              children: [
                SettingsRow.toggle(
                  title: _t('Sound effects', 'የድምፅ ውጤቶች'), // settings.sound
                  value: true,
                  onChanged: (_) {},
                ),
                SettingsRow.toggle(
                  title: _t('Vibration', 'ንዝረት'), // settings.haptics
                  value: false,
                  onChanged: (_) {},
                ),
                SettingsRow.toggle(
                  title: _t(
                    'Download upcoming songs on mobile data',
                    'ቀጣይ ዘፈኖችን በሞባይል ዳታ ያውርዱ',
                  ), // packs.mobilePrefetch
                  subtitle: _t(
                    'Off saves data: only songs already on your phone play.',
                    'ሲጠፋ ዳታ ይቆጥባል፤ በስልክዎ ላይ ያሉ ዘፈኖች ብቻ ይጫወታሉ።',
                  ), // packs.mobilePrefetch.help
                  value: true,
                  onChanged: null,
                ),
              ],
            ),
          ]),
          section('Settings rows · link, badge, button', [
            SettingsGroup(
              children: [
                SettingsRow(
                  title: _t('Privacy policy', 'የግላዊነት ፖሊሲ'), // settings.privacy
                  onTap: _noop,
                ),
                SettingsRow(
                  title: _t(
                    'Offline play · 2 packs · 27 MB',
                    'ያለ ኢንተርኔት መጫወት · 2 ጥቅሎች · 27 ሜባ',
                  ), // settings.offline
                  subtitle: _t(
                    'Update available',
                    'ማሻሻያ አለ',
                  ), // packs.updateAvailable
                  subtitleColor: ColorTokens.correctText,
                  badge: true,
                  onTap: _noop,
                ),
                SettingsRow(
                  title: _t('Playing as a guest', 'በእንግድነት እየተጫወቱ ነው'),
                  onTap: null,
                  trailing: PrimaryButton(
                    label: _t('Sign in', 'ይግቡ'),
                    small: true,
                    expand: false,
                    onPressed: _noop,
                  ),
                ), // settings.guest, settings.signIn
                SettingsRow(
                  title: _t('Delete account', 'መለያ ይሰርዙ'), // settings.delete
                  titleColor: ColorTokens.textError,
                  onTap: _noop,
                ),
              ],
            ),
          ]),
          section('Segmented controls · light, on the hero', [
            SegmentedControl<int>(
              selected: 0,
              onChanged: (_) {},
              options: [
                SegmentOption(value: 0, label: _t('Song', 'ዘፈኑን')),
                SegmentOption(value: 1, label: _t('Artist', 'ዘፋኙን')),
              ],
            ), // mode.guess.*
            SegmentedControl<int>(
              compact: true,
              selected: 1,
              onChanged: (_) {},
              options: [
                SegmentOption(
                  value: 0,
                  label: _t('Easy · 10 s', 'ቀላል · 10 ሰከንድ'),
                ),
                SegmentOption(
                  value: 1,
                  label: _t('Medium · 5 s', 'መካከለኛ · 5 ሰከንድ'),
                ),
                SegmentOption(
                  value: 2,
                  label: _t('Hard · 3 s', 'ከባድ · 3 ሰከንድ'),
                ),
              ],
            ), // difficulty.*
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [ColorTokens.heroMiddle, ColorTokens.heroBottom],
                ),
                borderRadius: BorderRadius.circular(RadiusTokens.large),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.n12),
                child: SegmentedControl<int>(
                  style: SegmentedStyle.onHero,
                  selected: _am ? 0 : 1,
                  onChanged: (_) {},
                  options: const [
                    SegmentOption(
                      value: 0,
                      label: 'አማርኛ',
                      textLocale: Locale('am'),
                    ),
                    SegmentOption(
                      value: 1,
                      label: 'English',
                      textLocale: Locale('en'),
                    ),
                  ],
                ),
              ),
            ), // settings.language
          ]),
          section('Choice chips · selected, idle', [
            Wrap(
              spacing: SpacingTokens.n8,
              runSpacing: SpacingTokens.n8,
              children: [
                AppChoiceChip(
                  label: _t('Any genre', 'ማንኛውም ዘውግ'), // genre.any
                  selected: true,
                  onTap: _noop,
                ),
                AppChoiceChip(
                  label: _t('Tizita', 'ትዝታ'), // genre.tizita
                  selected: false,
                  onTap: _noop,
                ),
                AppChoiceChip(
                  label: _t('Ethio-jazz', 'ኢትዮ ጃዝ'), // genre.ethiojazz
                  selected: false,
                  onTap: _noop,
                ),
              ],
            ),
          ]),
          section('Mode cards · selected, with tag', [
            ModeCard(
              title: _t('Guess the Intro', 'መግቢያውን ይገምቱ'),
              description: _t(
                'The opening of the song. The classic.',
                'የዘፈኑ መጀመሪያ። የተለመደው ጨዋታ።',
              ),
              icon: Icons.music_note_rounded,
              iconColor: ColorTokens.paletteSun400,
              selected: true,
              onTap: _noop,
            ),
            ModeCard(
              title: _t('Guess from the Middle', 'ከመሀል ይገምቱ'),
              description: _t(
                "A clip from the middle. Harder, so it's worth more.",
                'ከዘፈኑ መሀል የተወሰደ ቅንጭብ። ስለሚከብድ ተጨማሪ ነጥብ ያስገኛል።',
              ),
              tag: '+25%', // mode.middle.tag
              icon: Icons.show_chart_rounded,
              iconColor: ColorTokens.paletteCoral,
              selected: false,
              onTap: _noop,
            ),
          ]),
          section('Hero banner, stat tiles and wordmark', [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [ColorTokens.heroMiddle, ColorTokens.heroBottom],
                ),
                borderRadius: BorderRadius.circular(RadiusTokens.large),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.n12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LogoTiles(semanticLabel: _t('Yeman Zefen', 'የማን ዘፈን')),
                    const SizedBox(height: SpacingTokens.n12),
                    DarkBanner(
                      icon: Icons.wifi_off_rounded,
                      text: _t(
                        "You're offline. You can still play the 25 built-in songs.",
                        'ከኢንተርኔት ውጭ ነዎት። አብረው የመጡትን 25 ዘፈኖች መጫወት ይችላሉ።',
                      ),
                    ), // offline.banner.builtInOnly
                    const SizedBox(height: SpacingTokens.n12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: StatTile.number(
                              label: _t('Your best', 'ምርጥ ውጤትዎ'),
                              number: '1,240',
                            ),
                          ), // home.best.label
                          const SizedBox(width: SpacingTokens.n10),
                          Expanded(
                            child: StatTile.text(
                              label: _t('Play button starts', 'ይጫወቱ የሚጀምረው'),
                              text: _t(
                                "The '80s · Intro · Easy",
                                'የ80ዎቹ · መግቢያ · ቀላል',
                              ),
                            ),
                          ), // home.quickPlay.label
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          section('Bottom bar · Home, Settings', [
            AppBottomBar(
              current: NavTab.home,
              homeLabel: _t('Home', 'መነሻ'),
              playLabel: _t('Play', 'ይጫወቱ'),
              settingsLabel: _t('Settings', 'ቅንብሮች'),
              onHome: _noop,
              onPlay: _noop,
              onSettings: _noop,
            ), // nav.*
            AppBottomBar(
              current: NavTab.settings,
              homeLabel: _t('Home', 'መነሻ'),
              playLabel: _t('Play', 'ይጫወቱ'),
              settingsLabel: _t('Settings', 'ቅንብሮች'),
              onHome: _noop,
              onPlay: _noop,
              onSettings: _noop,
            ),
          ]),
          section('Sign-in buttons · Apple, Google, email, signing in', [
            SsoButton(
              kind: SsoKind.apple,
              label: _t('Continue with Apple', 'በApple ይቀጥሉ'), // auth.apple
              onPressed: _noop,
            ),
            SsoButton(
              kind: SsoKind.google,
              label: _t('Continue with Google', 'በGoogle ይቀጥሉ'), // auth.google
              onPressed: _noop,
            ),
            SsoButton(
              kind: SsoKind.email,
              label: _t('Continue with email', 'በኢሜይል ይቀጥሉ'), // auth.email
              onPressed: _noop,
            ),
            SsoButton(
              kind: SsoKind.google,
              label: _t('Signing in…', 'በመግባት ላይ…'), // auth.signingIn
              busy: true,
              onPressed: null,
            ),
          ]),
          section('Leaderboard avatars · podium, row', [
            const Wrap(
              spacing: SpacingTokens.n12,
              runSpacing: SpacingTokens.n12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                AvatarTile(
                  bordered: true,
                  colorIndex: 3,
                  size: SizeTokens.podiumFirst,
                ),
                AvatarTile(
                  bordered: true,
                  colorIndex: 1,
                  size: SizeTokens.podiumOther,
                ),
                AvatarTile(colorIndex: 0, size: SizeTokens.leaderboardAvatar),
                AvatarTile(colorIndex: 2, size: SizeTokens.leaderboardAvatar),
              ],
            ),
          ]),
          section('Ad placeholder', [
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RadiusTokens.large),
                child: AdOverlay(
                  badge: _t('Ad · 3', 'ማስታወቂያ · 3'), // ad.label
                  caption: _t(
                    'Ads keep this game free',
                    'ጨዋታው ነፃ የሆነው በማስታወቂያ ነው',
                  ), // ad.interstitialCaption
                ),
              ),
            ),
          ]),
          section('Dialog and bottom sheet', [
            Builder(
              builder: (context) => SecondaryButton(
                label: _t('Show dialog', 'ንግግር አሳይ'),
                onPressed: () => showAppDialog(
                  context,
                  title: _t(
                    'Leave this game?',
                    'ጨዋታውን ያቋርጣሉ?',
                  ), // round.leave.title
                  body: _t(
                    "Your score for this game won't be saved.",
                    'የዚህ ጨዋታ ውጤት አይቀመጥም።',
                  ), // round.leave.body
                  confirmLabel: _t('Leave', 'ይውጡ'),
                  cancelLabel: _t('Keep playing', 'መጫወት ይቀጥሉ'),
                ),
              ),
            ),
            Builder(
              builder: (context) => SecondaryButton(
                label: _t('Show bottom sheet', 'ሰሌዳ አሳይ'),
                onPressed: () => showAppBottomSheet<void>(
                  context,
                  semanticLabel: _t(
                    'Hint: remove 2 answers',
                    'ፍንጭ፦ 2 መልሶችን ያስወግዱ',
                  ),
                  builder: (sheetContext) => _HintSheetBody(
                    title: _t(
                      'Hint: remove 2 answers',
                      'ፍንጭ፦ 2 መልሶችን ያስወግዱ',
                    ), // round.hint
                    terms: _t(
                      "Watch a short ad. This round's points are halved.",
                      'አጭር ማስታወቂያ ይመልከቱ። የዚህ ዙር ነጥብ በግማሽ ይቀንሳል።',
                    ), // round.hint.terms
                    watch: _t('Watch ad', 'ማስታወቂያ ይመልከቱ'), // round.hint.watch
                    no: _t('No thanks', 'አይ፣ ይቅር'), // round.hint.cancel
                    onClose: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _HintSheetBody extends StatelessWidget {
  const _HintSheetBody({
    required this.title,
    required this.terms,
    required this.watch,
    required this.no,
    required this.onClose,
  });

  final String title;
  final String terms;
  final String watch;
  final String no;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.titleSmall),
        const SizedBox(height: SpacingTokens.n8),
        Text(
          terms,
          style: text.body.copyWith(color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: SpacingTokens.n16),
        PrimaryButton(label: watch, onPressed: onClose),
        const SizedBox(height: SpacingTokens.n8),
        SecondaryButton(label: no, onPressed: onClose),
      ],
    );
  }
}
