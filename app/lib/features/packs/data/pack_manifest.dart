import 'dart:convert';

/// The only manifest schema this app understands. Newer schemas need a newer app.
const supportedManifestSchema = 1;

/// A pack slug, as the admin API accepts it (`api/src/routes/admin/packs.ts`).
/// The slug becomes part of file paths, so nothing else is allowed.
final packSlugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
const packSlugMaxLength = 60;

bool isValidPackSlug(String slug) =>
    slug.length <= packSlugMaxLength && packSlugPattern.hasMatch(slug);

class PackManifestException implements Exception {
  const PackManifestException(this.message);
  final String message;

  @override
  String toString() => 'PackManifestException: $message';
}

/// One downloadable clip: where it is, what it must hash to, and how big it is.
class ManifestClip {
  const ManifestClip({
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.lengthMs,
  });

  final String url;
  final String sha256;
  final int bytes;
  final int lengthMs;
}

class ManifestTrack {
  const ManifestTrack({
    required this.id,
    required this.titleAm,
    required this.titleLatin,
    required this.artistId,
    required this.generationId,
    required this.artistAm,
    required this.artistLatin,
    required this.releaseYear,
    required this.intro,
    required this.middle,
  });

  final int id;
  final String? titleAm;
  final String? titleLatin;
  final int artistId;

  /// The track's era, or null when it has none.
  final int? generationId;
  final String? artistAm;
  final String? artistLatin;
  final int? releaseYear;
  final ManifestClip intro;
  final ManifestClip middle;
}

/// The pack manifest, parsed from `packs/{slug}/v{n}/manifest.json`.
/// The contract is in `docs/pack-manifest.md`.
class PackManifest {
  const PackManifest({
    required this.slug,
    required this.version,
    required this.publishedAt,
    required this.nameAm,
    required this.nameEn,
    required this.tracks,
    required this.totalBytes,
  });

  final String slug;
  final int version;
  final int publishedAt;
  final String nameAm;
  final String nameEn;
  final List<ManifestTrack> tracks;
  final int totalBytes;

  static final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  /// Parses and checks a manifest. Throws [PackManifestException] for anything
  /// the app cannot safely install: an unknown schema, a missing checksum, or
  /// a malformed field. Unknown extra fields are ignored.
  factory PackManifest.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw PackManifestException('not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PackManifestException('manifest is not a JSON object');
    }

    final schema = decoded['schema'];
    if (schema != supportedManifestSchema) {
      throw PackManifestException('unsupported manifest schema: $schema');
    }

    final names = _object(decoded, 'names');
    final rawTracks = _list(decoded, 'tracks');
    if (rawTracks.isEmpty) {
      throw const PackManifestException('manifest has no tracks');
    }

    final tracks = <ManifestTrack>[];
    final seenIds = <int>{};
    for (final raw in rawTracks) {
      if (raw is! Map<String, dynamic>) {
        throw const PackManifestException('track is not a JSON object');
      }
      final track = _parseTrack(raw);
      if (!seenIds.add(track.id)) {
        throw PackManifestException('track ${track.id} appears more than once');
      }
      tracks.add(track);
    }

    final slug = _string(decoded, 'slug');
    if (!isValidPackSlug(slug)) {
      throw PackManifestException('"$slug" is not a valid pack slug');
    }

    final totalBytes = _int(decoded, 'totalBytes');
    final summed = tracks.fold<int>(
      0,
      (sum, t) => sum + t.intro.bytes + t.middle.bytes,
    );
    if (totalBytes != summed) {
      throw PackManifestException('totalBytes is $totalBytes, clips add up to $summed');
    }

    return PackManifest(
      slug: slug,
      version: _int(decoded, 'version'),
      publishedAt: _int(decoded, 'publishedAt'),
      nameAm: _string(names, 'am'),
      nameEn: _string(names, 'en'),
      tracks: List.unmodifiable(tracks),
      totalBytes: totalBytes,
    );
  }

  static ManifestTrack _parseTrack(Map<String, dynamic> raw) {
    final clips = _object(raw, 'clips');
    return ManifestTrack(
      id: _int(raw, 'id'),
      titleAm: _nullableString(raw, 'titleAm'),
      titleLatin: _nullableString(raw, 'titleLatin'),
      artistId: _int(raw, 'artistId'),
      generationId: _nullableInt(raw, 'generationId'),
      artistAm: _nullableString(raw, 'artistAm'),
      artistLatin: _nullableString(raw, 'artistLatin'),
      releaseYear: _nullableInt(raw, 'releaseYear'),
      intro: _parseClip(_object(clips, 'intro')),
      middle: _parseClip(_object(clips, 'middle')),
    );
  }

  static ManifestClip _parseClip(Map<String, dynamic> raw) {
    final sha = raw['sha256'];
    if (sha is! String || sha.isEmpty) {
      throw const PackManifestException('clip is missing sha256');
    }
    if (!_sha256Pattern.hasMatch(sha)) {
      throw PackManifestException('clip sha256 is not 64 lowercase hex characters');
    }
    final bytes = _int(raw, 'bytes');
    if (bytes <= 0) {
      throw const PackManifestException('clip bytes must be positive');
    }
    return ManifestClip(
      url: _string(raw, 'url'),
      sha256: sha,
      bytes: bytes,
      lengthMs: _int(raw, 'lengthMs'),
    );
  }

  static Map<String, dynamic> _object(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! Map<String, dynamic>) throw PackManifestException('$key must be an object');
    return v;
  }

  static List<Object?> _list(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! List) throw PackManifestException('$key must be a list');
    return v;
  }

  static String _string(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! String || v.isEmpty) throw PackManifestException('$key must be a non-empty string');
    return v;
  }

  static String? _nullableString(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is! String) throw PackManifestException('$key must be a string or null');
    return v;
  }

  static int _int(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! int) throw PackManifestException('$key must be an integer');
    return v;
  }

  static int? _nullableInt(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is! int) throw PackManifestException('$key must be an integer or null');
    return v;
  }
}
