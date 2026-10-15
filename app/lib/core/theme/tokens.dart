// GENERATED FILE. DO NOT EDIT.
// Source: docs/design/tokens.json. Regenerate with: dart run tool/gen_tokens.dart
// dart format off

import 'package:flutter/material.dart';

import 'token_types.dart';

abstract final class ColorTokens {
  /// Cream: fade under the hero, sheet top, light text on dark
  static const Color paletteSun50 = Color(0xFFFFF3D1);
  static const Color paletteSun200 = Color(0xFFFFE07A);
  static const Color paletteSun300 = Color(0xFFFFDF6E);
  /// Brand yellow
  static const Color paletteSun400 = Color(0xFFFFC93C);
  static const Color paletteSun500 = Color(0xFFFFB02E);
  static const Color paletteSun550 = Color(0xFFFFAE2E);
  /// Orange end of full-screen yellow backgrounds
  static const Color paletteSun600 = Color(0xFFFFA94D);
  /// Press edge of yellow buttons
  static const Color paletteSun800 = Color(0xFFD99418);
  /// Always with ink text, never white (white on coral is ~3.4:1)
  static const Color paletteCoral = Color(0xFFF0563A);
  static const Color paletteSage = Color(0xFF7FB5A8);
  static const Color paletteSand = Color(0xFFE3C9A0);
  static const Color paletteLavender = Color(0xFFC9B8EC);
  /// Primary text and dark surfaces
  static const Color paletteInk = Color(0xFF2B2118);
  /// Secondary text
  static const Color paletteInk700 = Color(0xFF4A3B2E);
  /// Text on the yellow hero
  static const Color paletteInk650 = Color(0xFF3A2D22);
  /// Press edge of dark surfaces
  static const Color paletteInkDeep = Color(0xFF120D09);
  /// Top stop of dark card gradients
  static const Color paletteSlate = Color(0xFF2E3D39);
  /// Bottom stop of cards, segmented-control track
  static const Color paletteCream100 = Color(0xFFFBF4E8);
  /// Dividers, progress track
  static const Color paletteCream200 = Color(0xFFF1E8DA);
  /// Press edge of cards
  static const Color paletteCream300 = Color(0xFFEDE3D2);
  static const Color paletteWhite = Color(0xFFFFFFFF);
  static const Color paletteTeal500 = Color(0xFF2A8A77);
  static const Color paletteTeal700 = Color(0xFF1D6658);
  static const Color paletteTeal900 = Color(0xFF144A40);
  static const Color paletteRed500 = Color(0xFFDC4A30);
  static const Color paletteRed700 = Color(0xFFB8321B);
  static const Color paletteRed900 = Color(0xFF8A2614);
  /// Body area below the hero
  static const Color backgroundScreen = paletteWhite;
  /// Body area starts cream and fades to white over 140 px, under the hero's curve
  static const Color backgroundHeroFade = paletteSun50;
  /// Faint mint at the bottom of the round screen
  static const Color backgroundScreenFoot = Color(0xFFF3FAF8);
  /// Behind bottom sheets
  static const Color backgroundScrim = Color(0x732B2118);
  /// Full-screen ad placeholder, gradient to adOverlayEnd
  static const Color backgroundAdOverlay = paletteInk;
  static const Color backgroundAdOverlayEnd = Color(0xFF1C1510);
  /// Gradient white → cream100
  static const Color surfaceCard = paletteWhite;
  static const Color surfaceCardEnd = paletteCream100;
  static const Color surfaceCardEdge = paletteCream300;
  /// Stat tiles on the Home hero
  static const Color surfaceCardOnYellow = Color(0xB3FFFFFF);
  /// Selected options, Leaderboard row, offline banner. Gradient slate → ink
  static const Color surfaceDark = paletteInk;
  static const Color surfaceDarkEdge = paletteInkDeep;
  /// Segmented-control track on the yellow hero (Settings language)
  static const Color surfaceSegmentTrackOnHero = Color(0x73FFFFFF);
  static const Color surfaceSegmentTrack = paletteCream100;
  static const Color surfaceDivider = paletteCream200;
  /// Loading skeleton on a yellow screen; the shimmer sweeps to skeletonOnYellowHighlight
  static const Color surfaceSkeletonOnYellow = Color(0x59FFFFFF);
  static const Color surfaceSkeletonOnYellowHighlight = Color(0xBFFFFFFF);
  /// Loading skeleton on a white or cream body; the shimmer sweeps to skeletonOnLightHighlight
  static const Color surfaceSkeletonOnLight = paletteCream100;
  static const Color surfaceSkeletonOnLightHighlight = paletteWhite;
  /// Continue with Apple: black, gradient appleButtonTop to appleButton (Apple's guidelines)
  static const Color surfaceAppleButton = Color(0xFF111111);
  static const Color surfaceAppleButtonTop = Color(0xFF2E2620);
  static const Color surfaceAppleButtonEdge = Color(0xFF000000);
  /// Inline error card, gradient #FFF1EC → #FFE3DA, edge #F4C7B8
  static const Color surfaceErrorCard = Color(0xFFFFF1EC);
  static const Color surfaceErrorCardEnd = Color(0xFFFFE3DA);
  static const Color surfaceErrorCardEdge = Color(0xFFF4C7B8);
  /// Buttons: gradient sun200 0% → sun400 50% → sun550 100%
  static const Color primaryFill = paletteSun400;
  static const Color primaryFillTop = paletteSun200;
  static const Color primaryFillBottom = paletteSun550;
  static const Color primaryEdge = paletteSun800;
  static const Color primaryOnFill = paletteInk;
  /// Icons and selected text on dark surfaces
  static const Color primaryAccentOnDark = paletteSun400;
  /// Hero gradient: sun300 0% → sun400 55% → sun500 100%, plus a white radial glow (45% → 0) behind the focal element
  static const Color heroTop = paletteSun300;
  static const Color heroMiddle = paletteSun400;
  static const Color heroBottom = paletteSun500;
  /// Leaderboard and loading screens, which are yellow top to bottom
  static const Color heroFullScreenBottom = paletteSun600;
  static const Color heroGlow = Color(0x73FFFFFF);
  static const Color textPrimary = paletteInk;
  static const Color textSecondary = paletteInk700;
  static const Color textOnHero = paletteInk650;
  static const Color textOnDark = paletteSun50;
  static const Color textOnDarkMuted = paletteSand;
  /// Text on correct and wrong answer tiles
  static const Color textOnAnswerState = paletteWhite;
  static const Color textError = paletteRed900;
  /// Gradient teal500 → teal700. Always paired with a check icon and the word 'Correct'
  static const Color correctFill = paletteTeal700;
  static const Color correctFillTop = paletteTeal500;
  static const Color correctEdge = paletteTeal900;
  static const Color correctGlow = Color(0x5923786A);
  /// 'Correct +143' heading on white
  static const Color correctText = paletteTeal700;
  /// Gradient red500 → red700. Always paired with an X icon and 'Your pick'
  static const Color wrongFill = paletteRed700;
  static const Color wrongFillTop = paletteRed500;
  static const Color wrongEdge = paletteRed900;
  static const Color wrongGlow = Color(0x59D23C22);
  /// 'Not this one' / 'Time's up' heading on white
  static const Color wrongText = paletteRed700;
  /// Unpicked, incorrect tiles during feedback
  static const double answerDimOpacity = 0.45;
  /// Tiles removed by the hint; not tappable, no shadow
  static const double answerRemovedOpacity = 0.18;
  static const Color timerTrack = Color(0x8CFFFFFF);
  /// Gradient left to right teal500 → sage
  static const Color timerFill = paletteTeal500;
  static const Color timerFillEnd = paletteSage;
  /// Seconds-left pill; reads 'Paused' while the hint sheet or rewarded ad is up
  static const Color timerPill = paletteWhite;
  /// Gradient teal500 → teal700, white knob
  static const Color toggleOn = paletteTeal700;
  static const Color toggleKnob = paletteWhite;
  /// All eras: white → cream100 card
  static const Color eraAll = paletteWhite;
  /// Golden Age, before 1980
  static const Color eraGolden = paletteSun400;
  static const Color era80s = paletteCoral;
  static const Color era90s = paletteSage;
  static const Color era2000s = paletteSand;
  /// 2010 and later
  static const Color eraModern = paletteLavender;
  /// 3 px outline, 2 px offset
  static const Color eraSelectedRing = paletteInk;
  /// Gradient #4A3B2E → ink
  static const Color cassetteBody = Color(0xFF4A3B2E);
  /// Gradient #FF8A5C → #E0452A
  static const Color cassetteLabel = Color(0xFFFF8A5C);
  static const Color cassetteLabelEnd = Color(0xFFE0452A);
  /// Gradient sun400 → sun200
  static const Color cassetteStripe = paletteSun400;
  static const Color cassetteWindow = paletteInk;
  /// Gradient #5A4636 → #3B2F25, also the bottom tab
  static const Color cassetteTape = Color(0xFF5A4636);
  static const Color cassetteReelHub = paletteSun400;
  static const Color cassetteReel = paletteSun50;
  /// Bottom of the tape strip and tab gradient (tape -> tapeEnd)
  static const Color cassetteTapeEnd = Color(0xFF3B2F25);
  /// Translucent ring around the cassette body
  static const Color cassetteRim = Color(0x4DFFFFFF);
  static const Color cassetteGlow = Color(0x73F0563A);
  static const String logoTilesSequence = 'white, sage, white | coral, white, sand';
}

abstract final class TypeTokens {
  /// Font family. Fallbacks in the design: sans-serif.
  static const String familyLatin = 'Poppins';
  /// Font family. Fallbacks in the design: sans-serif.
  static const String familyEthiopic = 'Noto Sans Ethiopic';
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightExtrabold = FontWeight.w800;
  static const double lineHeightLatin = 1.4;
  /// Fidel needs the extra room for its marks
  static const double lineHeightEthiopic = 1.55;
  /// Era setup, Offline play, Settings: screens with many rows
  static const double lineHeightEthiopicDense = 1.5;
  /// The big total on Results: Poppins numerals need no extra room
  static const double lineHeightScore = 1.05;
  /// Headings in both scripts
  static const double lineHeightHeading = 1.35;
  /// Meta lines, stat labels, answer marks
  static const double scaleCaptionFontSize = 12.0;
  /// Meta lines, stat labels, answer marks
  static const FontWeight scaleCaptionFontWeight = FontWeight.w600;
  /// Chips, section headers, small buttons
  static const double scaleLabelFontSize = 13.0;
  /// Chips, section headers, small buttons
  static const FontWeight scaleLabelFontWeight = FontWeight.w700;
  /// List row titles
  static const double scaleBodySmallFontSize = 14.0;
  /// List row titles
  static const FontWeight scaleBodySmallFontWeight = FontWeight.w700;
  static const double scaleBodyFontSize = 15.0;
  static const FontWeight scaleBodyFontWeight = FontWeight.w400;
  /// Answer tiles, intro paragraphs (400)
  static const double scaleBodyLargeFontSize = 16.0;
  /// Answer tiles, intro paragraphs (400)
  static const FontWeight scaleBodyLargeFontWeight = FontWeight.w700;
  /// Primary buttons; the Play button in the bar is 18
  static const double scaleButtonFontSize = 17.0;
  /// Primary buttons; the Play button in the bar is 18
  static const FontWeight scaleButtonFontWeight = FontWeight.w800;
  /// Screen titles, round question
  static const double scaleTitleSmallFontSize = 20.0;
  /// Screen titles, round question
  static const FontWeight scaleTitleSmallFontWeight = FontWeight.w800;
  /// Feedback heading, message screens, Home greeting
  static const double scaleTitleFontSize = 24.0;
  /// Feedback heading, message screens, Home greeting
  static const FontWeight scaleTitleFontWeight = FontWeight.w800;
  /// Welcome and onboarding
  static const double scaleDisplayFontSize = 26.0;
  /// Welcome and onboarding
  static const FontWeight scaleDisplayFontWeight = FontWeight.w800;
  /// Results total, Poppins
  static const double scaleScoreFontSize = 52.0;
  /// Results total, Poppins
  static const FontWeight scaleScoreFontWeight = FontWeight.w800;
  /// Every screen must fit at 1.3 on a 360-wide screen
  static const double textScaleMax = 1.3;
}

abstract final class SpacingTokens {
  static const double n2 = 2.0;
  static const double n4 = 4.0;
  static const double n6 = 6.0;
  static const double n8 = 8.0;
  static const double n10 = 10.0;
  /// Default gap between cards and answer tiles
  static const double n12 = 12.0;
  static const double n14 = 14.0;
  /// Screen side padding in the body
  static const double n16 = 16.0;
  /// Screen side padding in the hero
  static const double n18 = 18.0;
  static const double n20 = 20.0;
  /// Hero and body bottom padding on Mode select and Settings
  static const double n22 = 22.0;
  static const double n24 = 24.0;
  /// Hero bottom padding; side padding of the bottom bar
  static const double n26 = 26.0;
  /// Body top padding under the hero (hero overlaps by 12)
  static const double n28 = 28.0;
  /// Hero top padding on Home
  static const double n30 = 30.0;
  static const double n32 = 32.0;
  /// Body starts 12 px under the hero so the curve sits over the cream fade
  static const double heroOverlap = -12.0;
  /// Minimum hit area for anything tappable
  static const double touchTargetMin = 48.0;
}

abstract final class RadiusTokens {
  static const double progress = 4.0;
  /// Chips, timer pill, logo tiles (9–12)
  static const double pill = 12.0;
  /// Small buttons, segmented-control items, icon tiles
  static const double small = 14.0;
  /// List cards, pack rows, segmented-control track (16–18)
  static const double card = 18.0;
  /// Answer tiles, primary buttons, option rows
  static const double large = 20.0;
  static const double playButton = 22.0;
  /// Large option cards on Mode select
  static const double modeCard = 22.0;
  /// Icon tile on the large mode cards
  static const double modeIcon = 16.0;
  /// Message-screen icon badge (120 × 120)
  static const double badge = 36.0;
  static const BorderRadius bottomBar = BorderRadius.only(topLeft: Radius.circular(36.0), topRight: Radius.circular(36.0), bottomRight: Radius.circular(0.0), bottomLeft: Radius.circular(0.0));
  static const BorderRadius sheet = BorderRadius.only(topLeft: Radius.circular(32.0), topRight: Radius.circular(32.0), bottomRight: Radius.circular(0.0), bottomLeft: Radius.circular(0.0));
  /// Curved bottom of the yellow hero; heroDense on denser screens
  static const BorderRadius hero = BorderRadius.only(topLeft: Radius.circular(0.0), topRight: Radius.circular(0.0), bottomRight: Radius.circular(44.0), bottomLeft: Radius.circular(44.0));
  /// Curved bottom of the hero on era setup, Settings and Offline play
  static const BorderRadius heroDense = BorderRadius.only(topLeft: Radius.circular(0.0), topRight: Radius.circular(0.0), bottomRight: Radius.circular(40.0), bottomLeft: Radius.circular(40.0));
}

abstract final class ElevationTokens {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0xFFEDE3D2), offset: Offset(0.0, 4.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x0F2B2118), offset: Offset(0.0, 8.0), blurRadius: 18.0),
  ];
  static const List<BoxShadow> row = [
    BoxShadow(color: Color(0xFFEDE3D2), offset: Offset(0.0, 5.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x142B2118), offset: Offset(0.0, 10.0), blurRadius: 22.0),
  ];
  static const List<BoxShadow> answer = [
    BoxShadow(color: Color(0xFFEDE3D2), offset: Offset(0.0, 6.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x1A2B2118), offset: Offset(0.0, 12.0), blurRadius: 26.0),
  ];
  static const List<BoxShadow> answerCorrect = [
    BoxShadow(color: Color(0xFF144A40), offset: Offset(0.0, 6.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x5923786A), offset: Offset(0.0, 12.0), blurRadius: 28.0),
  ];
  static const List<BoxShadow> answerWrong = [
    BoxShadow(color: Color(0xFF8A2614), offset: Offset(0.0, 6.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x59D23C22), offset: Offset(0.0, 12.0), blurRadius: 28.0),
  ];
  static const List<BoxShadow> primary = [
    BoxShadow(color: Color(0xFFD99418), offset: Offset(0.0, 6.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x66FFAA2E), offset: Offset(0.0, 12.0), blurRadius: 26.0),
  ];
  /// Inset parts of [primary], painted as a highlight by InsetGloss.
  static const List<InsetShadow> primaryInset = [
    InsetShadow(color: Color(0x99FFFFFF), dx: 0.0, dy: 2.0, blur: 0.0),
  ];
  static const List<BoxShadow> primarySmall = [
    BoxShadow(color: Color(0xFFD99418), offset: Offset(0.0, 4.0), blurRadius: 0.0),
  ];
  static const List<BoxShadow> dark = [
    BoxShadow(color: Color(0xFF120D09), offset: Offset(0.0, 5.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x332B2118), offset: Offset(0.0, 10.0), blurRadius: 22.0),
  ];
  static const List<BoxShadow> iconButton = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0.0, 4.0), blurRadius: 0.0),
  ];
  static const List<BoxShadow> chip = [
    BoxShadow(color: Color(0x1F000000), offset: Offset(0.0, 3.0), blurRadius: 0.0),
  ];
  /// Inset parts of [chip], painted as a highlight by InsetGloss.
  static const List<InsetShadow> chipInset = [
    InsetShadow(color: Color(0x61FFFFFF), dx: 0.0, dy: 10.0, blur: 12.0),
  ];
  static const List<BoxShadow> hero = [
    BoxShadow(color: Color(0x59FFB02E), offset: Offset(0.0, 14.0), blurRadius: 30.0),
  ];
  static const List<BoxShadow> bottomBar = [
    BoxShadow(color: Color(0x47FFA94D), offset: Offset(0.0, -10.0), blurRadius: 26.0),
  ];
  /// Press edge under the Apple button (color.surface.appleButtonEdge)
  static const List<BoxShadow> appleButton = [
    BoxShadow(color: Color(0xFF000000), offset: Offset(0.0, 5.0), blurRadius: 0.0),
  ];
  /// Press edge under the inline error card (color.surface.errorCardEdge)
  static const List<BoxShadow> errorCard = [
    BoxShadow(color: Color(0xFFF4C7B8), offset: Offset(0.0, 4.0), blurRadius: 0.0),
  ];
  /// Inset parts of [gloss], painted as a highlight by InsetGloss.
  static const List<InsetShadow> glossInset = [
    InsetShadow(color: Color(0x61FFFFFF), dx: 0.0, dy: 10.0, blur: 12.0),
  ];
  /// Under and around the cassette; the rim is size.cassetteRim
  static const List<BoxShadow> cassette = [
    BoxShadow(color: Color(0x26000000), offset: Offset(0.0, 8.0), blurRadius: 0.0),
    BoxShadow(color: Color(0x73F0563A), offset: Offset(0.0, 0.0), blurRadius: 46.0),
  ];
}

abstract final class SizeTokens {
  /// Back button; 52 in the bottom bar
  static const double iconButton = 48.0;
  /// Wordmark tile on the first-launch screen
  static const double logoTileLarge = 40.0;
  /// Hero height on the message screens (consent, update, out of songs, error)
  static const double messageHero = 360.0;
  /// Icon badge on the message screens; radius.badge
  static const double messageBadge = 120.0;
  static const double messageBadgeIcon = 56.0;
  /// Hero height on the welcome screen
  static const double welcomeHero = 400.0;
  /// Onboarding page dots
  static const double pageDotWidth = 8.0;
  /// Onboarding page dots
  static const double pageDotActiveWidth = 24.0;
  /// Height of a text line in a loading skeleton
  static const double skeletonLine = 12.0;
  /// Wordmark tile on Home (40 on first launch); radius.pill
  static const double logoTile = 30.0;
  /// First place avatar on the leaderboard podium
  static const double podiumFirst = 68.0;
  /// Second and third place avatars
  static const double podiumOther = 52.0;
  /// Avatar in a leaderboard row
  static const double leaderboardAvatar = 30.0;
  static const double leaderboardRowMinHeight = 50.0;
  /// The crown over first place
  static const double crownWidth = 26.0;
  /// The crown over first place
  static const double crownHeight = 20.0;
  /// Length of the cream-to-white fade under the hero's curve (color.background.heroFade)
  static const double heroFadeHeight = 140.0;
  /// Home and Settings icon buttons in the bottom bar
  static const double navButton = 52.0;
  /// Icon tile on the large mode cards (Mode select); radius.modeIcon
  static const double modeIconTile = 52.0;
  static const double playButtonMinWidth = 140.0;
  static const double playButtonHeight = 62.0;
  /// 2 × 2 grid, 12 gap
  static const double answerTileMinHeight = 84.0;
  static const double primaryButtonMinHeight = 58.0;
  static const double secondaryButtonMinHeight = 54.0;
  static const double listRowMinHeight = 64.0;
  static const double eraCardMinHeight = 52.0;
  /// Display chips; tappable genre chips are 44 with padding to 48 hit area
  static const double chipMinHeight = 34.0;
  static const double toggleWidth = 46.0;
  static const double toggleHeight = 28.0;
  /// White knob, inset toggleKnobInset from the track
  static const double toggleKnob = 22.0;
  static const double toggleKnobInset = 3.0;
  static const double timerBarHeight = 8.0;
  static const double cassetteWidth = 200.0;
  static const double cassetteHeight = 128.0;
  /// Line icons, 24 grid; 2.5 for chevrons, 3 for check/X marks
  static const double iconStroke = 2.0;
  /// Small buttons (Download, Sign in); their hit area is still touchTargetMin
  static const double smallButtonMinHeight = 44.0;
  /// Check/X marks, chevrons in tiles
  static const double iconSmall = 16.0;
  /// Back arrows, inline icons
  static const double icon = 20.0;
  /// Icons on tiles and the hint button
  static const double iconLarge = 24.0;
  /// Coloured square behind a row or pack icon (radius.small)
  static const double iconTile = 44.0;
  /// Dividers
  static const double hairline = 1.0;
  /// Selected era card outline
  static const double eraRing = 3.0;
  static const double eraRingOffset = 2.0;
  /// Bottom sheet handle
  static const double grabberWidth = 40.0;
  static const double grabberHeight = 4.0;
  static const double packProgressHeight = 6.0;
  /// Ring around the cassette body (color.cassette.rim)
  static const double cassetteRim = 8.0;
  static const double cassettePadding = 9.0;
  static const double cassetteGap = 7.0;
  /// Dark pill holding the reels
  static const double cassetteWindowHeight = 42.0;
  /// Reel diameter
  static const double cassetteReel = 30.0;
  static const double cassetteStripeHeight = 5.0;
  /// Tape strip between the reels
  static const double cassetteTapeHeight = 12.0;
  /// Tab under the label
  static const double cassetteTabHeight = 16.0;
  /// Tab side margin
  static const double cassetteTabInset = 32.0;
}

abstract final class MotionTokens {
  /// Button and tile press (translate by edge height)
  static const Duration durationPress = Duration(milliseconds: 120);
  /// Opacity changes: dimming, hint-removed
  static const Duration durationFade = Duration(milliseconds: 200);
  /// Correct/wrong reveal: scale 0.96 → 1.03 (60%) → 1
  static const Duration durationAnswerPop = Duration(milliseconds: 300);
  /// One turn of a cassette reel, repeats while the clip plays
  static const Duration durationReelSpin = Duration(milliseconds: 1200);
  /// Skeleton sweep, repeats
  static const Duration durationShimmer = Duration(milliseconds: 1400);
  /// Timer bar update rate
  static const Duration durationTimerTick = Duration(milliseconds: 100);
  /// CSS 'ease': press, fade, pop
  static const Cubic easingStandard = Cubic(0.25, 0.1, 0.25, 1.0);
  /// Reel spin, shimmer, timer bar
  static const Cubic easingLinear = Cubic(0.0, 0.0, 1.0, 1.0);
  static const String reducedMotion = 'No reel spin, no pop (state change is instant), static skeletons. Timers and durations below are unchanged.';
}

abstract final class TimingTokens {
  /// Correct reveal, then auto-advance
  static const Duration feedbackCorrect = Duration(milliseconds: 1000);
  /// Wrong or time-out reveal; a tap anywhere skips it
  static const Duration feedbackWrong = Duration(milliseconds: 5000);
  /// Hint sheet auto-closes; the round timer is paused while it is open and while the rewarded ad plays
  static const Duration hintSheetMax = Duration(milliseconds: 8000);
  /// Show a skeleton only if loading takes longer than this
  static const Duration skeletonDelay = Duration(milliseconds: 300);
  /// Round waits for a clip download at most this long, then is skipped without penalty (docs/architecture.md, play-first delivery)
  static const Duration nextSongWaitMax = Duration(milliseconds: 10000);
  /// Mandatory interstitial after every 3rd round; served from /v1/config
  static const int interstitialEveryRounds = 3;
}
