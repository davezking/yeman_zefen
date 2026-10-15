import 'models.dart';

/// Mock data for the prototype. No service is involved: the screens show
/// these lists as they are.
///
/// The names are invented, to look like a real catalog without attributing
/// songs to real people. The one real pair is "Ere Mela Mela" by Mahmoud Ahmed,
/// the pair the design boards use.
const mockTracks = <Track>[
  // Golden Age (before 1980)
  Track(
    id: 't01',
    titleAm: 'እሬ መላ መላ',
    titleLatin: 'Ere Mela Mela',
    artistAm: 'ማሕሙድ አሕመድ',
    artistLatin: 'Mahmoud Ahmed',
    generationId: EraId.golden,
    genre: Genre.ethiojazz,
  ),
  Track(
    id: 't02',
    titleAm: 'የሐሙስ ምሽት',
    titleLatin: 'Yehamus Mishit',
    artistAm: 'ተስፋዬ ወልደማርያም',
    artistLatin: 'Tesfaye Woldemariam',
    generationId: EraId.golden,
    genre: Genre.tizita,
  ),
  Track(
    id: 't03',
    titleAm: 'ጎጃም ሰማይ',
    titleLatin: 'Gojjam Semay',
    artistAm: 'አበበች ሰይፉ',
    artistLatin: 'Abebech Seifu',
    generationId: EraId.golden,
    genre: Genre.traditional,
  ),
  Track(
    id: 't04',
    titleAm: 'አዲስ አበባ ማታ',
    titleLatin: 'Addis Abeba Mata',
    artistAm: 'ሙሉነህ ገብሬ',
    artistLatin: 'Mulune Gebre',
    generationId: EraId.golden,
    genre: Genre.ethiojazz,
  ),
  // The '80s
  Track(
    id: 't05',
    titleAm: 'ትዝታ ዘመን',
    titleLatin: 'Tizita Zemen',
    artistAm: 'ሄለን ተስፋዬ',
    artistLatin: 'Helen Tesfaye',
    generationId: EraId.eighties,
    genre: Genre.tizita,
  ),
  Track(
    id: 't06',
    titleAm: 'የልብ ሰላም',
    titleLatin: 'Yelib Selam',
    artistAm: 'ዳዊት ካሳሁን',
    artistLatin: 'Dawit Kassahun',
    generationId: EraId.eighties,
    genre: Genre.pop,
  ),
  Track(
    id: 't07',
    titleAm: 'ሀገሬ ሸዋ',
    titleLatin: 'Hagere Shewa',
    artistAm: 'ፀሐይ መንግሥቱ',
    artistLatin: 'Tsehay Mengistu',
    generationId: EraId.eighties,
    genre: Genre.traditional,
  ),
  Track(
    id: 't08',
    titleAm: 'ቡና ቤት',
    titleLatin: 'Buna Bet',
    artistAm: 'ኃይሉ በላይ',
    artistLatin: 'Hailu Belay',
    generationId: EraId.eighties,
    genre: Genre.ethiojazz,
  ),
  // The '90s
  Track(
    id: 't09',
    titleAm: 'እንደ ጽጌረዳ',
    titleLatin: 'Ende Tsigereda',
    artistAm: 'ሠላማዊት ዓለሙ',
    artistLatin: 'Selamawit Alemu',
    generationId: EraId.nineties,
    genre: Genre.pop,
  ),
  Track(
    id: 't10',
    titleAm: 'የናፍቆት ደብዳቤ',
    titleLatin: 'Yenafkot Debdabe',
    artistAm: 'ብሩክ ታዬ',
    artistLatin: 'Biruk Taye',
    generationId: EraId.nineties,
    genre: Genre.pop,
  ),
  Track(
    id: 't11',
    titleAm: 'ዘመን ሲቀየር',
    titleLatin: 'Zemen Sikeyer',
    artistAm: 'መሰለ ደግፌ',
    artistLatin: 'Mesele Degefe',
    generationId: EraId.nineties,
    genre: Genre.tizita,
  ),
  Track(
    id: 't12',
    titleAm: 'እናት ሀገሬ',
    titleLatin: 'Enat Hagere',
    artistAm: 'አልማዝ ወንድሙ',
    artistLatin: 'Almaz Wondimu',
    generationId: EraId.nineties,
    genre: Genre.traditional,
  ),
  // The 2000s
  Track(
    id: 't13',
    titleAm: 'ሰላም ነው',
    titleLatin: 'Selam New',
    artistAm: 'ዮናስ ሐጎስ',
    artistLatin: 'Yonas Hagos',
    generationId: EraId.twoThousands,
    genre: Genre.hiphop,
  ),
  Track(
    id: 't14',
    titleAm: 'ፍቅር በጋራ',
    titleLatin: 'Fikir Begara',
    artistAm: 'ሰብለ ከበደ',
    artistLatin: 'Sebel Kebede',
    generationId: EraId.twoThousands,
    genre: Genre.pop,
  ),
  Track(
    id: 't15',
    titleAm: 'ባለቤቴ',
    titleLatin: 'Balebete',
    artistAm: 'ምስጋናው ደሴ',
    artistLatin: 'Misganaw Desse',
    generationId: EraId.twoThousands,
    genre: Genre.traditional,
  ),
  Track(
    id: 't16',
    titleAm: 'የጎዳና ላይ ፍቅር',
    titleLatin: 'Yegodana Lay Fikir',
    artistAm: 'ናሆም ሰለሞን',
    artistLatin: 'Nahom Solomon',
    generationId: EraId.twoThousands,
    genre: Genre.hiphop,
  ),
  // Modern (2010 and later)
  Track(
    id: 't17',
    titleAm: 'ሂድ ልሂድ',
    titleLatin: 'Hid Lehid',
    artistAm: 'ቤተልሔም አሰፋ',
    artistLatin: 'Betelhem Assefa',
    generationId: EraId.modern,
    genre: Genre.pop,
  ),
  Track(
    id: 't18',
    titleAm: 'ከፍታ',
    titleLatin: 'Kefta',
    artistAm: 'ሩት ዮሐንስ',
    artistLatin: 'Ruth Yohannes',
    generationId: EraId.modern,
    genre: Genre.pop,
  ),
  Track(
    id: 't19',
    titleAm: 'ምድር ላይ',
    titleLatin: 'Midir Lay',
    artistAm: 'ዳንኤል ተስፋዬ',
    artistLatin: 'Daniel Tesfaye',
    generationId: EraId.modern,
    genre: Genre.hiphop,
  ),
  Track(
    id: 't20',
    titleAm: 'አዲስ ቀን',
    titleLatin: 'Addis Qen',
    artistAm: 'ሄርሞን ገብረሕይወት',
    artistLatin: 'Hermon Gebrehiwot',
    generationId: EraId.modern,
    genre: Genre.tizita,
  ),
];

/// The songs that ship inside the app, by era: 25 in all, five in each, about
/// 8 MB. They are enough to play "All eras", but too few to play one era.
const mockBuiltInSongsByEra = <int, int>{
  EraId.golden: 5,
  EraId.eighties: 5,
  EraId.nineties: 5,
  EraId.twoThousands: 5,
  EraId.modern: 5,
};

int get mockBuiltInSongCount =>
    mockBuiltInSongsByEra.values.fold(0, (a, b) => a + b);

/// Four packs in four different states: installed, downloading, available
/// and an update waiting.
const mockPacks = <PackItem>[
  PackItem(
    id: 'p-80s',
    nameAm: 'የ80ዎቹ',
    nameEn: "The '80s",
    generationId: EraId.eighties,
    songCount: 40,
    sizeMb: 12,
    status: PackStatus.installed,
  ),
  PackItem(
    id: 'p-golden',
    nameAm: 'ወርቃማው ዘመን',
    nameEn: 'Golden Age',
    generationId: EraId.golden,
    songCount: 60,
    sizeMb: 18,
    status: PackStatus.downloading,
    progress: 0.42,
  ),
  PackItem(
    id: 'p-90s',
    nameAm: 'የ90ዎቹ',
    nameEn: "The '90s",
    generationId: EraId.nineties,
    songCount: 45,
    sizeMb: 14,
  ),
  PackItem(
    id: 'p-2000s',
    nameAm: 'የ2000ዎቹ',
    nameEn: 'The 2000s',
    generationId: EraId.twoThousands,
    songCount: 50,
    sizeMb: 15,
    status: PackStatus.updateAvailable,
    updateSizeMb: 3,
  ),
];

/// Clip-cache use: prefetched clips, capped at 50 MB by default.
const mockCache = CacheUsage(usedMb: 31, capMb: 50);

/// A guest who has played before.
const mockGuest = UserInfo.guest(bestScore: 1240);

/// A guest who has never finished a game: Home shows "Play a game to set your first best score."
const mockNewGuest = UserInfo.guest();

/// A signed-in player.
const mockSignedIn = UserInfo.signedIn(
  displayName: 'Meron T.',
  bestScore: 1240,
  weeklyRank: 7,
);

const mockAppVersion = '1.0.0';

/// A leaderboard of invented players. The board differs a little by era and is
/// larger for all time, so the filters can be seen to do something.
List<LeaderboardEntry> mockLeaderboard(
  LeaderboardScope scope,
  int generationId,
) {
  const names = [
    'Selam T.',
    'Dawit A.',
    'Hanna G.',
    'Yonas M.',
    'Meron K.',
    'Abel W.',
    'Liya B.',
    'Kidus H.',
    'Rahel D.',
    'Samson F.',
    'Bethel S.',
    'Natnael Z.',
  ];
  const weekly = [
    9860,
    9412,
    8975,
    8630,
    8204,
    7991,
    7640,
    7302,
    6988,
    6540,
    6120,
    5733,
  ];
  final factor = scope == LeaderboardScope.allTime ? 7 : 1;
  // Each era starts the list at a different player.
  final shift = generationId % names.length;
  return [
    for (var i = 0; i < names.length; i++)
      LeaderboardEntry(
        rank: i + 1,
        name: names[(i + shift) % names.length],
        points: (weekly[i] * factor * (generationId == 0 ? 1 : 0.6)).round(),
        colorIndex: switch (i) {
          0 => 3,
          1 => 1,
          2 => 2,
          _ => i,
        },
      ),
  ];
}

/// The signed-in player's own row on that board: [weeklyRank] this week,
/// further down all time, and lower on a single era's board.
LeaderboardEntry mockMyEntry(
  LeaderboardScope scope,
  int generationId,
  int weeklyRank,
) {
  final allTime = scope == LeaderboardScope.allTime;
  final rank = (allTime ? weeklyRank + 12 : weeklyRank) + generationId;
  final weekly = 7640 - (weeklyRank - 7) * 300;
  return LeaderboardEntry(
    rank: rank,
    name: 'Meron T.',
    points: ((allTime ? weekly * 3 : weekly) * (generationId == 0 ? 1 : 0.6))
        .round(),
    colorIndex: 5,
  );
}
