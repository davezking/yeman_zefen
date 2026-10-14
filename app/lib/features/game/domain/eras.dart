/// The five eras (generations), by id. The ids and order are the seed in
/// `api/migrations/0001_seed.sql`. Admin-editable names are not fetched yet.
const eraNames = <int, String>{
  1: 'Golden Age',
  2: "The '80s",
  3: "The '90s",
  4: 'The 2000s',
  5: 'Modern',
};

/// 0 is "all eras", as in the leaderboard and the session payload.
String eraName(int generationId) => generationId == 0 ? 'All eras' : (eraNames[generationId] ?? 'Era $generationId');
