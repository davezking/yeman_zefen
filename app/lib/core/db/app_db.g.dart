// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $InstalledPacksTable extends InstalledPacks
    with TableInfo<$InstalledPacksTable, InstalledPack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstalledPacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<int> installedAt = GeneratedColumn<int>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    slug,
    version,
    manifestJson,
    installedAt,
    totalBytes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installed_packs';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstalledPack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_totalBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slug};
  @override
  InstalledPack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstalledPack(
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installed_at'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
    );
  }

  @override
  $InstalledPacksTable createAlias(String alias) {
    return $InstalledPacksTable(attachedDatabase, alias);
  }
}

class InstalledPack extends DataClass implements Insertable<InstalledPack> {
  final String slug;
  final int version;
  final String manifestJson;
  final int installedAt;
  final int totalBytes;
  const InstalledPack({
    required this.slug,
    required this.version,
    required this.manifestJson,
    required this.installedAt,
    required this.totalBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slug'] = Variable<String>(slug);
    map['version'] = Variable<int>(version);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['installed_at'] = Variable<int>(installedAt);
    map['total_bytes'] = Variable<int>(totalBytes);
    return map;
  }

  InstalledPacksCompanion toCompanion(bool nullToAbsent) {
    return InstalledPacksCompanion(
      slug: Value(slug),
      version: Value(version),
      manifestJson: Value(manifestJson),
      installedAt: Value(installedAt),
      totalBytes: Value(totalBytes),
    );
  }

  factory InstalledPack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstalledPack(
      slug: serializer.fromJson<String>(json['slug']),
      version: serializer.fromJson<int>(json['version']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      installedAt: serializer.fromJson<int>(json['installedAt']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slug': serializer.toJson<String>(slug),
      'version': serializer.toJson<int>(version),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'installedAt': serializer.toJson<int>(installedAt),
      'totalBytes': serializer.toJson<int>(totalBytes),
    };
  }

  InstalledPack copyWith({
    String? slug,
    int? version,
    String? manifestJson,
    int? installedAt,
    int? totalBytes,
  }) => InstalledPack(
    slug: slug ?? this.slug,
    version: version ?? this.version,
    manifestJson: manifestJson ?? this.manifestJson,
    installedAt: installedAt ?? this.installedAt,
    totalBytes: totalBytes ?? this.totalBytes,
  );
  InstalledPack copyWithCompanion(InstalledPacksCompanion data) {
    return InstalledPack(
      slug: data.slug.present ? data.slug.value : this.slug,
      version: data.version.present ? data.version.value : this.version,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstalledPack(')
          ..write('slug: $slug, ')
          ..write('version: $version, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('installedAt: $installedAt, ')
          ..write('totalBytes: $totalBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(slug, version, manifestJson, installedAt, totalBytes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledPack &&
          other.slug == this.slug &&
          other.version == this.version &&
          other.manifestJson == this.manifestJson &&
          other.installedAt == this.installedAt &&
          other.totalBytes == this.totalBytes);
}

class InstalledPacksCompanion extends UpdateCompanion<InstalledPack> {
  final Value<String> slug;
  final Value<int> version;
  final Value<String> manifestJson;
  final Value<int> installedAt;
  final Value<int> totalBytes;
  final Value<int> rowid;
  const InstalledPacksCompanion({
    this.slug = const Value.absent(),
    this.version = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstalledPacksCompanion.insert({
    required String slug,
    required int version,
    required String manifestJson,
    required int installedAt,
    required int totalBytes,
    this.rowid = const Value.absent(),
  }) : slug = Value(slug),
       version = Value(version),
       manifestJson = Value(manifestJson),
       installedAt = Value(installedAt),
       totalBytes = Value(totalBytes);
  static Insertable<InstalledPack> custom({
    Expression<String>? slug,
    Expression<int>? version,
    Expression<String>? manifestJson,
    Expression<int>? installedAt,
    Expression<int>? totalBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (slug != null) 'slug': slug,
      if (version != null) 'version': version,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (installedAt != null) 'installed_at': installedAt,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstalledPacksCompanion copyWith({
    Value<String>? slug,
    Value<int>? version,
    Value<String>? manifestJson,
    Value<int>? installedAt,
    Value<int>? totalBytes,
    Value<int>? rowid,
  }) {
    return InstalledPacksCompanion(
      slug: slug ?? this.slug,
      version: version ?? this.version,
      manifestJson: manifestJson ?? this.manifestJson,
      installedAt: installedAt ?? this.installedAt,
      totalBytes: totalBytes ?? this.totalBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<int>(installedAt.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstalledPacksCompanion(')
          ..write('slug: $slug, ')
          ..write('version: $version, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('installedAt: $installedAt, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTracksTable extends LocalTracks
    with TableInfo<$LocalTracksTable, LocalTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packSlugMeta = const VerificationMeta(
    'packSlug',
  );
  @override
  late final GeneratedColumn<String> packSlug = GeneratedColumn<String>(
    'pack_slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleAmMeta = const VerificationMeta(
    'titleAm',
  );
  @override
  late final GeneratedColumn<String> titleAm = GeneratedColumn<String>(
    'title_am',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleLatinMeta = const VerificationMeta(
    'titleLatin',
  );
  @override
  late final GeneratedColumn<String> titleLatin = GeneratedColumn<String>(
    'title_latin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistAmMeta = const VerificationMeta(
    'artistAm',
  );
  @override
  late final GeneratedColumn<String> artistAm = GeneratedColumn<String>(
    'artist_am',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistLatinMeta = const VerificationMeta(
    'artistLatin',
  );
  @override
  late final GeneratedColumn<String> artistLatin = GeneratedColumn<String>(
    'artist_latin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistIdMeta = const VerificationMeta(
    'artistId',
  );
  @override
  late final GeneratedColumn<int> artistId = GeneratedColumn<int>(
    'artist_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generationIdMeta = const VerificationMeta(
    'generationId',
  );
  @override
  late final GeneratedColumn<int> generationId = GeneratedColumn<int>(
    'generation_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releaseYearMeta = const VerificationMeta(
    'releaseYear',
  );
  @override
  late final GeneratedColumn<int> releaseYear = GeneratedColumn<int>(
    'release_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introPathMeta = const VerificationMeta(
    'introPath',
  );
  @override
  late final GeneratedColumn<String> introPath = GeneratedColumn<String>(
    'intro_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _middlePathMeta = const VerificationMeta(
    'middlePath',
  );
  @override
  late final GeneratedColumn<String> middlePath = GeneratedColumn<String>(
    'middle_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    packSlug,
    id,
    titleAm,
    titleLatin,
    artistAm,
    artistLatin,
    artistId,
    generationId,
    releaseYear,
    introPath,
    middlePath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pack_slug')) {
      context.handle(
        _packSlugMeta,
        packSlug.isAcceptableOrUnknown(data['pack_slug']!, _packSlugMeta),
      );
    } else if (isInserting) {
      context.missing(_packSlugMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title_am')) {
      context.handle(
        _titleAmMeta,
        titleAm.isAcceptableOrUnknown(data['title_am']!, _titleAmMeta),
      );
    }
    if (data.containsKey('title_latin')) {
      context.handle(
        _titleLatinMeta,
        titleLatin.isAcceptableOrUnknown(data['title_latin']!, _titleLatinMeta),
      );
    }
    if (data.containsKey('artist_am')) {
      context.handle(
        _artistAmMeta,
        artistAm.isAcceptableOrUnknown(data['artist_am']!, _artistAmMeta),
      );
    }
    if (data.containsKey('artist_latin')) {
      context.handle(
        _artistLatinMeta,
        artistLatin.isAcceptableOrUnknown(
          data['artist_latin']!,
          _artistLatinMeta,
        ),
      );
    }
    if (data.containsKey('artist_id')) {
      context.handle(
        _artistIdMeta,
        artistId.isAcceptableOrUnknown(data['artist_id']!, _artistIdMeta),
      );
    }
    if (data.containsKey('generation_id')) {
      context.handle(
        _generationIdMeta,
        generationId.isAcceptableOrUnknown(
          data['generation_id']!,
          _generationIdMeta,
        ),
      );
    }
    if (data.containsKey('release_year')) {
      context.handle(
        _releaseYearMeta,
        releaseYear.isAcceptableOrUnknown(
          data['release_year']!,
          _releaseYearMeta,
        ),
      );
    }
    if (data.containsKey('intro_path')) {
      context.handle(
        _introPathMeta,
        introPath.isAcceptableOrUnknown(data['intro_path']!, _introPathMeta),
      );
    }
    if (data.containsKey('middle_path')) {
      context.handle(
        _middlePathMeta,
        middlePath.isAcceptableOrUnknown(data['middle_path']!, _middlePathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packSlug, id};
  @override
  LocalTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTrack(
      packSlug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_slug'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      titleAm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_am'],
      ),
      titleLatin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_latin'],
      ),
      artistAm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_am'],
      ),
      artistLatin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_latin'],
      ),
      artistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}artist_id'],
      ),
      generationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation_id'],
      ),
      releaseYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}release_year'],
      ),
      introPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro_path'],
      ),
      middlePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}middle_path'],
      ),
    );
  }

  @override
  $LocalTracksTable createAlias(String alias) {
    return $LocalTracksTable(attachedDatabase, alias);
  }
}

class LocalTrack extends DataClass implements Insertable<LocalTrack> {
  final String packSlug;
  final int id;
  final String? titleAm;
  final String? titleLatin;
  final String? artistAm;
  final String? artistLatin;

  /// The artist's catalog id and the track's era (generation). The round engine
  /// needs both to build same-era and distinct-artist options. Nullable because
  /// rows written before schema 2 do not have them, and an era can be unknown.
  final int? artistId;
  final int? generationId;
  final int? releaseYear;
  final String? introPath;
  final String? middlePath;
  const LocalTrack({
    required this.packSlug,
    required this.id,
    this.titleAm,
    this.titleLatin,
    this.artistAm,
    this.artistLatin,
    this.artistId,
    this.generationId,
    this.releaseYear,
    this.introPath,
    this.middlePath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pack_slug'] = Variable<String>(packSlug);
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || titleAm != null) {
      map['title_am'] = Variable<String>(titleAm);
    }
    if (!nullToAbsent || titleLatin != null) {
      map['title_latin'] = Variable<String>(titleLatin);
    }
    if (!nullToAbsent || artistAm != null) {
      map['artist_am'] = Variable<String>(artistAm);
    }
    if (!nullToAbsent || artistLatin != null) {
      map['artist_latin'] = Variable<String>(artistLatin);
    }
    if (!nullToAbsent || artistId != null) {
      map['artist_id'] = Variable<int>(artistId);
    }
    if (!nullToAbsent || generationId != null) {
      map['generation_id'] = Variable<int>(generationId);
    }
    if (!nullToAbsent || releaseYear != null) {
      map['release_year'] = Variable<int>(releaseYear);
    }
    if (!nullToAbsent || introPath != null) {
      map['intro_path'] = Variable<String>(introPath);
    }
    if (!nullToAbsent || middlePath != null) {
      map['middle_path'] = Variable<String>(middlePath);
    }
    return map;
  }

  LocalTracksCompanion toCompanion(bool nullToAbsent) {
    return LocalTracksCompanion(
      packSlug: Value(packSlug),
      id: Value(id),
      titleAm: titleAm == null && nullToAbsent
          ? const Value.absent()
          : Value(titleAm),
      titleLatin: titleLatin == null && nullToAbsent
          ? const Value.absent()
          : Value(titleLatin),
      artistAm: artistAm == null && nullToAbsent
          ? const Value.absent()
          : Value(artistAm),
      artistLatin: artistLatin == null && nullToAbsent
          ? const Value.absent()
          : Value(artistLatin),
      artistId: artistId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistId),
      generationId: generationId == null && nullToAbsent
          ? const Value.absent()
          : Value(generationId),
      releaseYear: releaseYear == null && nullToAbsent
          ? const Value.absent()
          : Value(releaseYear),
      introPath: introPath == null && nullToAbsent
          ? const Value.absent()
          : Value(introPath),
      middlePath: middlePath == null && nullToAbsent
          ? const Value.absent()
          : Value(middlePath),
    );
  }

  factory LocalTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTrack(
      packSlug: serializer.fromJson<String>(json['packSlug']),
      id: serializer.fromJson<int>(json['id']),
      titleAm: serializer.fromJson<String?>(json['titleAm']),
      titleLatin: serializer.fromJson<String?>(json['titleLatin']),
      artistAm: serializer.fromJson<String?>(json['artistAm']),
      artistLatin: serializer.fromJson<String?>(json['artistLatin']),
      artistId: serializer.fromJson<int?>(json['artistId']),
      generationId: serializer.fromJson<int?>(json['generationId']),
      releaseYear: serializer.fromJson<int?>(json['releaseYear']),
      introPath: serializer.fromJson<String?>(json['introPath']),
      middlePath: serializer.fromJson<String?>(json['middlePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packSlug': serializer.toJson<String>(packSlug),
      'id': serializer.toJson<int>(id),
      'titleAm': serializer.toJson<String?>(titleAm),
      'titleLatin': serializer.toJson<String?>(titleLatin),
      'artistAm': serializer.toJson<String?>(artistAm),
      'artistLatin': serializer.toJson<String?>(artistLatin),
      'artistId': serializer.toJson<int?>(artistId),
      'generationId': serializer.toJson<int?>(generationId),
      'releaseYear': serializer.toJson<int?>(releaseYear),
      'introPath': serializer.toJson<String?>(introPath),
      'middlePath': serializer.toJson<String?>(middlePath),
    };
  }

  LocalTrack copyWith({
    String? packSlug,
    int? id,
    Value<String?> titleAm = const Value.absent(),
    Value<String?> titleLatin = const Value.absent(),
    Value<String?> artistAm = const Value.absent(),
    Value<String?> artistLatin = const Value.absent(),
    Value<int?> artistId = const Value.absent(),
    Value<int?> generationId = const Value.absent(),
    Value<int?> releaseYear = const Value.absent(),
    Value<String?> introPath = const Value.absent(),
    Value<String?> middlePath = const Value.absent(),
  }) => LocalTrack(
    packSlug: packSlug ?? this.packSlug,
    id: id ?? this.id,
    titleAm: titleAm.present ? titleAm.value : this.titleAm,
    titleLatin: titleLatin.present ? titleLatin.value : this.titleLatin,
    artistAm: artistAm.present ? artistAm.value : this.artistAm,
    artistLatin: artistLatin.present ? artistLatin.value : this.artistLatin,
    artistId: artistId.present ? artistId.value : this.artistId,
    generationId: generationId.present ? generationId.value : this.generationId,
    releaseYear: releaseYear.present ? releaseYear.value : this.releaseYear,
    introPath: introPath.present ? introPath.value : this.introPath,
    middlePath: middlePath.present ? middlePath.value : this.middlePath,
  );
  LocalTrack copyWithCompanion(LocalTracksCompanion data) {
    return LocalTrack(
      packSlug: data.packSlug.present ? data.packSlug.value : this.packSlug,
      id: data.id.present ? data.id.value : this.id,
      titleAm: data.titleAm.present ? data.titleAm.value : this.titleAm,
      titleLatin: data.titleLatin.present
          ? data.titleLatin.value
          : this.titleLatin,
      artistAm: data.artistAm.present ? data.artistAm.value : this.artistAm,
      artistLatin: data.artistLatin.present
          ? data.artistLatin.value
          : this.artistLatin,
      artistId: data.artistId.present ? data.artistId.value : this.artistId,
      generationId: data.generationId.present
          ? data.generationId.value
          : this.generationId,
      releaseYear: data.releaseYear.present
          ? data.releaseYear.value
          : this.releaseYear,
      introPath: data.introPath.present ? data.introPath.value : this.introPath,
      middlePath: data.middlePath.present
          ? data.middlePath.value
          : this.middlePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTrack(')
          ..write('packSlug: $packSlug, ')
          ..write('id: $id, ')
          ..write('titleAm: $titleAm, ')
          ..write('titleLatin: $titleLatin, ')
          ..write('artistAm: $artistAm, ')
          ..write('artistLatin: $artistLatin, ')
          ..write('artistId: $artistId, ')
          ..write('generationId: $generationId, ')
          ..write('releaseYear: $releaseYear, ')
          ..write('introPath: $introPath, ')
          ..write('middlePath: $middlePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    packSlug,
    id,
    titleAm,
    titleLatin,
    artistAm,
    artistLatin,
    artistId,
    generationId,
    releaseYear,
    introPath,
    middlePath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTrack &&
          other.packSlug == this.packSlug &&
          other.id == this.id &&
          other.titleAm == this.titleAm &&
          other.titleLatin == this.titleLatin &&
          other.artistAm == this.artistAm &&
          other.artistLatin == this.artistLatin &&
          other.artistId == this.artistId &&
          other.generationId == this.generationId &&
          other.releaseYear == this.releaseYear &&
          other.introPath == this.introPath &&
          other.middlePath == this.middlePath);
}

class LocalTracksCompanion extends UpdateCompanion<LocalTrack> {
  final Value<String> packSlug;
  final Value<int> id;
  final Value<String?> titleAm;
  final Value<String?> titleLatin;
  final Value<String?> artistAm;
  final Value<String?> artistLatin;
  final Value<int?> artistId;
  final Value<int?> generationId;
  final Value<int?> releaseYear;
  final Value<String?> introPath;
  final Value<String?> middlePath;
  final Value<int> rowid;
  const LocalTracksCompanion({
    this.packSlug = const Value.absent(),
    this.id = const Value.absent(),
    this.titleAm = const Value.absent(),
    this.titleLatin = const Value.absent(),
    this.artistAm = const Value.absent(),
    this.artistLatin = const Value.absent(),
    this.artistId = const Value.absent(),
    this.generationId = const Value.absent(),
    this.releaseYear = const Value.absent(),
    this.introPath = const Value.absent(),
    this.middlePath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTracksCompanion.insert({
    required String packSlug,
    required int id,
    this.titleAm = const Value.absent(),
    this.titleLatin = const Value.absent(),
    this.artistAm = const Value.absent(),
    this.artistLatin = const Value.absent(),
    this.artistId = const Value.absent(),
    this.generationId = const Value.absent(),
    this.releaseYear = const Value.absent(),
    this.introPath = const Value.absent(),
    this.middlePath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : packSlug = Value(packSlug),
       id = Value(id);
  static Insertable<LocalTrack> custom({
    Expression<String>? packSlug,
    Expression<int>? id,
    Expression<String>? titleAm,
    Expression<String>? titleLatin,
    Expression<String>? artistAm,
    Expression<String>? artistLatin,
    Expression<int>? artistId,
    Expression<int>? generationId,
    Expression<int>? releaseYear,
    Expression<String>? introPath,
    Expression<String>? middlePath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packSlug != null) 'pack_slug': packSlug,
      if (id != null) 'id': id,
      if (titleAm != null) 'title_am': titleAm,
      if (titleLatin != null) 'title_latin': titleLatin,
      if (artistAm != null) 'artist_am': artistAm,
      if (artistLatin != null) 'artist_latin': artistLatin,
      if (artistId != null) 'artist_id': artistId,
      if (generationId != null) 'generation_id': generationId,
      if (releaseYear != null) 'release_year': releaseYear,
      if (introPath != null) 'intro_path': introPath,
      if (middlePath != null) 'middle_path': middlePath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTracksCompanion copyWith({
    Value<String>? packSlug,
    Value<int>? id,
    Value<String?>? titleAm,
    Value<String?>? titleLatin,
    Value<String?>? artistAm,
    Value<String?>? artistLatin,
    Value<int?>? artistId,
    Value<int?>? generationId,
    Value<int?>? releaseYear,
    Value<String?>? introPath,
    Value<String?>? middlePath,
    Value<int>? rowid,
  }) {
    return LocalTracksCompanion(
      packSlug: packSlug ?? this.packSlug,
      id: id ?? this.id,
      titleAm: titleAm ?? this.titleAm,
      titleLatin: titleLatin ?? this.titleLatin,
      artistAm: artistAm ?? this.artistAm,
      artistLatin: artistLatin ?? this.artistLatin,
      artistId: artistId ?? this.artistId,
      generationId: generationId ?? this.generationId,
      releaseYear: releaseYear ?? this.releaseYear,
      introPath: introPath ?? this.introPath,
      middlePath: middlePath ?? this.middlePath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packSlug.present) {
      map['pack_slug'] = Variable<String>(packSlug.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (titleAm.present) {
      map['title_am'] = Variable<String>(titleAm.value);
    }
    if (titleLatin.present) {
      map['title_latin'] = Variable<String>(titleLatin.value);
    }
    if (artistAm.present) {
      map['artist_am'] = Variable<String>(artistAm.value);
    }
    if (artistLatin.present) {
      map['artist_latin'] = Variable<String>(artistLatin.value);
    }
    if (artistId.present) {
      map['artist_id'] = Variable<int>(artistId.value);
    }
    if (generationId.present) {
      map['generation_id'] = Variable<int>(generationId.value);
    }
    if (releaseYear.present) {
      map['release_year'] = Variable<int>(releaseYear.value);
    }
    if (introPath.present) {
      map['intro_path'] = Variable<String>(introPath.value);
    }
    if (middlePath.present) {
      map['middle_path'] = Variable<String>(middlePath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTracksCompanion(')
          ..write('packSlug: $packSlug, ')
          ..write('id: $id, ')
          ..write('titleAm: $titleAm, ')
          ..write('titleLatin: $titleLatin, ')
          ..write('artistAm: $artistAm, ')
          ..write('artistLatin: $artistLatin, ')
          ..write('artistId: $artistId, ')
          ..write('generationId: $generationId, ')
          ..write('releaseYear: $releaseYear, ')
          ..write('introPath: $introPath, ')
          ..write('middlePath: $middlePath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingSessionsTable extends PendingSessions
    with TableInfo<$PendingSessionsTable, PendingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _parkedMeta = const VerificationMeta('parked');
  @override
  late final GeneratedColumn<bool> parked = GeneratedColumn<bool>(
    'parked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("parked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payloadJson,
    createdAt,
    attempts,
    lastError,
    nextAttemptAt,
    parked,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('parked')) {
      context.handle(
        _parkedMeta,
        parked.isAcceptableOrUnknown(data['parked']!, _parkedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      parked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}parked'],
      )!,
    );
  }

  @override
  $PendingSessionsTable createAlias(String alias) {
    return $PendingSessionsTable(attachedDatabase, alias);
  }
}

class PendingSession extends DataClass implements Insertable<PendingSession> {
  final String id;
  final String payloadJson;
  final int createdAt;
  final int attempts;
  final String? lastError;

  /// Not sent before this time (epoch ms, UTC): the backoff after a failed attempt. 0 = send now.
  final int nextAttemptAt;

  /// The API refused the session for good (a 4xx), so it is never sent again. The row stays for
  /// debugging, with [lastError] saying why.
  final bool parked;
  const PendingSession({
    required this.id,
    required this.payloadJson,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    required this.nextAttemptAt,
    required this.parked,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<int>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    map['parked'] = Variable<bool>(parked);
    return map;
  }

  PendingSessionsCompanion toCompanion(bool nullToAbsent) {
    return PendingSessionsCompanion(
      id: Value(id),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      nextAttemptAt: Value(nextAttemptAt),
      parked: Value(parked),
    );
  }

  factory PendingSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSession(
      id: serializer.fromJson<String>(json['id']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      nextAttemptAt: serializer.fromJson<int>(json['nextAttemptAt']),
      parked: serializer.fromJson<bool>(json['parked']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'nextAttemptAt': serializer.toJson<int>(nextAttemptAt),
      'parked': serializer.toJson<bool>(parked),
    };
  }

  PendingSession copyWith({
    String? id,
    String? payloadJson,
    int? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    int? nextAttemptAt,
    bool? parked,
  }) => PendingSession(
    id: id ?? this.id,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    parked: parked ?? this.parked,
  );
  PendingSession copyWithCompanion(PendingSessionsCompanion data) {
    return PendingSession(
      id: data.id.present ? data.id.value : this.id,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      parked: data.parked.present ? data.parked.value : this.parked,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSession(')
          ..write('id: $id, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('parked: $parked')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payloadJson,
    createdAt,
    attempts,
    lastError,
    nextAttemptAt,
    parked,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSession &&
          other.id == this.id &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.parked == this.parked);
}

class PendingSessionsCompanion extends UpdateCompanion<PendingSession> {
  final Value<String> id;
  final Value<String> payloadJson;
  final Value<int> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> nextAttemptAt;
  final Value<bool> parked;
  final Value<int> rowid;
  const PendingSessionsCompanion({
    this.id = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.parked = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSessionsCompanion.insert({
    required String id,
    required String payloadJson,
    required int createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.parked = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<PendingSession> custom({
    Expression<String>? id,
    Expression<String>? payloadJson,
    Expression<int>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? nextAttemptAt,
    Expression<bool>? parked,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (parked != null) 'parked': parked,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? payloadJson,
    Value<int>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? nextAttemptAt,
    Value<bool>? parked,
    Value<int>? rowid,
  }) {
    return PendingSessionsCompanion(
      id: id ?? this.id,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      parked: parked ?? this.parked,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (parked.present) {
      map['parked'] = Variable<bool>(parked.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('parked: $parked, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalBestsTable extends LocalBests
    with TableInfo<$LocalBestsTable, LocalBest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalBestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generationIdMeta = const VerificationMeta(
    'generationId',
  );
  @override
  late final GeneratedColumn<int> generationId = GeneratedColumn<int>(
    'generation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bestScoreMeta = const VerificationMeta(
    'bestScore',
  );
  @override
  late final GeneratedColumn<int> bestScore = GeneratedColumn<int>(
    'best_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _achievedAtMeta = const VerificationMeta(
    'achievedAt',
  );
  @override
  late final GeneratedColumn<int> achievedAt = GeneratedColumn<int>(
    'achieved_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mode,
    generationId,
    bestScore,
    achievedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_bests';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalBest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('generation_id')) {
      context.handle(
        _generationIdMeta,
        generationId.isAcceptableOrUnknown(
          data['generation_id']!,
          _generationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generationIdMeta);
    }
    if (data.containsKey('best_score')) {
      context.handle(
        _bestScoreMeta,
        bestScore.isAcceptableOrUnknown(data['best_score']!, _bestScoreMeta),
      );
    } else if (isInserting) {
      context.missing(_bestScoreMeta);
    }
    if (data.containsKey('achieved_at')) {
      context.handle(
        _achievedAtMeta,
        achievedAt.isAcceptableOrUnknown(data['achieved_at']!, _achievedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_achievedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mode, generationId};
  @override
  LocalBest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalBest(
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      generationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation_id'],
      )!,
      bestScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}best_score'],
      )!,
      achievedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}achieved_at'],
      )!,
    );
  }

  @override
  $LocalBestsTable createAlias(String alias) {
    return $LocalBestsTable(attachedDatabase, alias);
  }
}

class LocalBest extends DataClass implements Insertable<LocalBest> {
  final String mode;
  final int generationId;
  final int bestScore;
  final int achievedAt;
  const LocalBest({
    required this.mode,
    required this.generationId,
    required this.bestScore,
    required this.achievedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mode'] = Variable<String>(mode);
    map['generation_id'] = Variable<int>(generationId);
    map['best_score'] = Variable<int>(bestScore);
    map['achieved_at'] = Variable<int>(achievedAt);
    return map;
  }

  LocalBestsCompanion toCompanion(bool nullToAbsent) {
    return LocalBestsCompanion(
      mode: Value(mode),
      generationId: Value(generationId),
      bestScore: Value(bestScore),
      achievedAt: Value(achievedAt),
    );
  }

  factory LocalBest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalBest(
      mode: serializer.fromJson<String>(json['mode']),
      generationId: serializer.fromJson<int>(json['generationId']),
      bestScore: serializer.fromJson<int>(json['bestScore']),
      achievedAt: serializer.fromJson<int>(json['achievedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mode': serializer.toJson<String>(mode),
      'generationId': serializer.toJson<int>(generationId),
      'bestScore': serializer.toJson<int>(bestScore),
      'achievedAt': serializer.toJson<int>(achievedAt),
    };
  }

  LocalBest copyWith({
    String? mode,
    int? generationId,
    int? bestScore,
    int? achievedAt,
  }) => LocalBest(
    mode: mode ?? this.mode,
    generationId: generationId ?? this.generationId,
    bestScore: bestScore ?? this.bestScore,
    achievedAt: achievedAt ?? this.achievedAt,
  );
  LocalBest copyWithCompanion(LocalBestsCompanion data) {
    return LocalBest(
      mode: data.mode.present ? data.mode.value : this.mode,
      generationId: data.generationId.present
          ? data.generationId.value
          : this.generationId,
      bestScore: data.bestScore.present ? data.bestScore.value : this.bestScore,
      achievedAt: data.achievedAt.present
          ? data.achievedAt.value
          : this.achievedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalBest(')
          ..write('mode: $mode, ')
          ..write('generationId: $generationId, ')
          ..write('bestScore: $bestScore, ')
          ..write('achievedAt: $achievedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mode, generationId, bestScore, achievedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalBest &&
          other.mode == this.mode &&
          other.generationId == this.generationId &&
          other.bestScore == this.bestScore &&
          other.achievedAt == this.achievedAt);
}

class LocalBestsCompanion extends UpdateCompanion<LocalBest> {
  final Value<String> mode;
  final Value<int> generationId;
  final Value<int> bestScore;
  final Value<int> achievedAt;
  final Value<int> rowid;
  const LocalBestsCompanion({
    this.mode = const Value.absent(),
    this.generationId = const Value.absent(),
    this.bestScore = const Value.absent(),
    this.achievedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalBestsCompanion.insert({
    required String mode,
    required int generationId,
    required int bestScore,
    required int achievedAt,
    this.rowid = const Value.absent(),
  }) : mode = Value(mode),
       generationId = Value(generationId),
       bestScore = Value(bestScore),
       achievedAt = Value(achievedAt);
  static Insertable<LocalBest> custom({
    Expression<String>? mode,
    Expression<int>? generationId,
    Expression<int>? bestScore,
    Expression<int>? achievedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mode != null) 'mode': mode,
      if (generationId != null) 'generation_id': generationId,
      if (bestScore != null) 'best_score': bestScore,
      if (achievedAt != null) 'achieved_at': achievedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalBestsCompanion copyWith({
    Value<String>? mode,
    Value<int>? generationId,
    Value<int>? bestScore,
    Value<int>? achievedAt,
    Value<int>? rowid,
  }) {
    return LocalBestsCompanion(
      mode: mode ?? this.mode,
      generationId: generationId ?? this.generationId,
      bestScore: bestScore ?? this.bestScore,
      achievedAt: achievedAt ?? this.achievedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (generationId.present) {
      map['generation_id'] = Variable<int>(generationId.value);
    }
    if (bestScore.present) {
      map['best_score'] = Variable<int>(bestScore.value);
    }
    if (achievedAt.present) {
      map['achieved_at'] = Variable<int>(achievedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalBestsCompanion(')
          ..write('mode: $mode, ')
          ..write('generationId: $generationId, ')
          ..write('bestScore: $bestScore, ')
          ..write('achievedAt: $achievedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCountersTable extends LocalCounters
    with TableInfo<$LocalCountersTable, LocalCounter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCountersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [name, count];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_counters';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCounter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  LocalCounter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCounter(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
    );
  }

  @override
  $LocalCountersTable createAlias(String alias) {
    return $LocalCountersTable(attachedDatabase, alias);
  }
}

class LocalCounter extends DataClass implements Insertable<LocalCounter> {
  final String name;
  final int count;
  const LocalCounter({required this.name, required this.count});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['count'] = Variable<int>(count);
    return map;
  }

  LocalCountersCompanion toCompanion(bool nullToAbsent) {
    return LocalCountersCompanion(name: Value(name), count: Value(count));
  }

  factory LocalCounter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCounter(
      name: serializer.fromJson<String>(json['name']),
      count: serializer.fromJson<int>(json['count']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'count': serializer.toJson<int>(count),
    };
  }

  LocalCounter copyWith({String? name, int? count}) =>
      LocalCounter(name: name ?? this.name, count: count ?? this.count);
  LocalCounter copyWithCompanion(LocalCountersCompanion data) {
    return LocalCounter(
      name: data.name.present ? data.name.value : this.name,
      count: data.count.present ? data.count.value : this.count,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCounter(')
          ..write('name: $name, ')
          ..write('count: $count')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, count);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCounter &&
          other.name == this.name &&
          other.count == this.count);
}

class LocalCountersCompanion extends UpdateCompanion<LocalCounter> {
  final Value<String> name;
  final Value<int> count;
  final Value<int> rowid;
  const LocalCountersCompanion({
    this.name = const Value.absent(),
    this.count = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCountersCompanion.insert({
    required String name,
    this.count = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<LocalCounter> custom({
    Expression<String>? name,
    Expression<int>? count,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (count != null) 'count': count,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCountersCompanion copyWith({
    Value<String>? name,
    Value<int>? count,
    Value<int>? rowid,
  }) {
    return LocalCountersCompanion(
      name: name ?? this.name,
      count: count ?? this.count,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCountersCompanion(')
          ..write('name: $name, ')
          ..write('count: $count, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentSessionsTable extends RecentSessions
    with TableInfo<$RecentSessionsTable, RecentSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<int> playedAt = GeneratedColumn<int>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdsJsonMeta = const VerificationMeta(
    'trackIdsJson',
  );
  @override
  late final GeneratedColumn<String> trackIdsJson = GeneratedColumn<String>(
    'track_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverScoreMeta = const VerificationMeta(
    'serverScore',
  );
  @override
  late final GeneratedColumn<int> serverScore = GeneratedColumn<int>(
    'server_score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    playedAt,
    trackIdsJson,
    serverScore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    if (data.containsKey('track_ids_json')) {
      context.handle(
        _trackIdsJsonMeta,
        trackIdsJson.isAcceptableOrUnknown(
          data['track_ids_json']!,
          _trackIdsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackIdsJsonMeta);
    }
    if (data.containsKey('server_score')) {
      context.handle(
        _serverScoreMeta,
        serverScore.isAcceptableOrUnknown(
          data['server_score']!,
          _serverScoreMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  RecentSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentSession(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}played_at'],
      )!,
      trackIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_ids_json'],
      )!,
      serverScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_score'],
      ),
    );
  }

  @override
  $RecentSessionsTable createAlias(String alias) {
    return $RecentSessionsTable(attachedDatabase, alias);
  }
}

class RecentSession extends DataClass implements Insertable<RecentSession> {
  final String sessionId;
  final int playedAt;
  final String trackIdsJson;

  /// The score the server computed once the session was uploaded; null until then.
  /// The server decides the real score, so a results list shows this over the local one.
  final int? serverScore;
  const RecentSession({
    required this.sessionId,
    required this.playedAt,
    required this.trackIdsJson,
    this.serverScore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['played_at'] = Variable<int>(playedAt);
    map['track_ids_json'] = Variable<String>(trackIdsJson);
    if (!nullToAbsent || serverScore != null) {
      map['server_score'] = Variable<int>(serverScore);
    }
    return map;
  }

  RecentSessionsCompanion toCompanion(bool nullToAbsent) {
    return RecentSessionsCompanion(
      sessionId: Value(sessionId),
      playedAt: Value(playedAt),
      trackIdsJson: Value(trackIdsJson),
      serverScore: serverScore == null && nullToAbsent
          ? const Value.absent()
          : Value(serverScore),
    );
  }

  factory RecentSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentSession(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      playedAt: serializer.fromJson<int>(json['playedAt']),
      trackIdsJson: serializer.fromJson<String>(json['trackIdsJson']),
      serverScore: serializer.fromJson<int?>(json['serverScore']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'playedAt': serializer.toJson<int>(playedAt),
      'trackIdsJson': serializer.toJson<String>(trackIdsJson),
      'serverScore': serializer.toJson<int?>(serverScore),
    };
  }

  RecentSession copyWith({
    String? sessionId,
    int? playedAt,
    String? trackIdsJson,
    Value<int?> serverScore = const Value.absent(),
  }) => RecentSession(
    sessionId: sessionId ?? this.sessionId,
    playedAt: playedAt ?? this.playedAt,
    trackIdsJson: trackIdsJson ?? this.trackIdsJson,
    serverScore: serverScore.present ? serverScore.value : this.serverScore,
  );
  RecentSession copyWithCompanion(RecentSessionsCompanion data) {
    return RecentSession(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
      trackIdsJson: data.trackIdsJson.present
          ? data.trackIdsJson.value
          : this.trackIdsJson,
      serverScore: data.serverScore.present
          ? data.serverScore.value
          : this.serverScore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentSession(')
          ..write('sessionId: $sessionId, ')
          ..write('playedAt: $playedAt, ')
          ..write('trackIdsJson: $trackIdsJson, ')
          ..write('serverScore: $serverScore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, playedAt, trackIdsJson, serverScore);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentSession &&
          other.sessionId == this.sessionId &&
          other.playedAt == this.playedAt &&
          other.trackIdsJson == this.trackIdsJson &&
          other.serverScore == this.serverScore);
}

class RecentSessionsCompanion extends UpdateCompanion<RecentSession> {
  final Value<String> sessionId;
  final Value<int> playedAt;
  final Value<String> trackIdsJson;
  final Value<int?> serverScore;
  final Value<int> rowid;
  const RecentSessionsCompanion({
    this.sessionId = const Value.absent(),
    this.playedAt = const Value.absent(),
    this.trackIdsJson = const Value.absent(),
    this.serverScore = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentSessionsCompanion.insert({
    required String sessionId,
    required int playedAt,
    required String trackIdsJson,
    this.serverScore = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       playedAt = Value(playedAt),
       trackIdsJson = Value(trackIdsJson);
  static Insertable<RecentSession> custom({
    Expression<String>? sessionId,
    Expression<int>? playedAt,
    Expression<String>? trackIdsJson,
    Expression<int>? serverScore,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (playedAt != null) 'played_at': playedAt,
      if (trackIdsJson != null) 'track_ids_json': trackIdsJson,
      if (serverScore != null) 'server_score': serverScore,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentSessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? playedAt,
    Value<String>? trackIdsJson,
    Value<int?>? serverScore,
    Value<int>? rowid,
  }) {
    return RecentSessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      playedAt: playedAt ?? this.playedAt,
      trackIdsJson: trackIdsJson ?? this.trackIdsJson,
      serverScore: serverScore ?? this.serverScore,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<int>(playedAt.value);
    }
    if (trackIdsJson.present) {
      map['track_ids_json'] = Variable<String>(trackIdsJson.value);
    }
    if (serverScore.present) {
      map['server_score'] = Variable<int>(serverScore.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentSessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('playedAt: $playedAt, ')
          ..write('trackIdsJson: $trackIdsJson, ')
          ..write('serverScore: $serverScore, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $InstalledPacksTable installedPacks = $InstalledPacksTable(this);
  late final $LocalTracksTable localTracks = $LocalTracksTable(this);
  late final $PendingSessionsTable pendingSessions = $PendingSessionsTable(
    this,
  );
  late final $LocalBestsTable localBests = $LocalBestsTable(this);
  late final $LocalCountersTable localCounters = $LocalCountersTable(this);
  late final $RecentSessionsTable recentSessions = $RecentSessionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    installedPacks,
    localTracks,
    pendingSessions,
    localBests,
    localCounters,
    recentSessions,
  ];
}

typedef $$InstalledPacksTableCreateCompanionBuilder =
    InstalledPacksCompanion Function({
      required String slug,
      required int version,
      required String manifestJson,
      required int installedAt,
      required int totalBytes,
      Value<int> rowid,
    });
typedef $$InstalledPacksTableUpdateCompanionBuilder =
    InstalledPacksCompanion Function({
      Value<String> slug,
      Value<int> version,
      Value<String> manifestJson,
      Value<int> installedAt,
      Value<int> totalBytes,
      Value<int> rowid,
    });

class $$InstalledPacksTableFilterComposer
    extends Composer<_$AppDb, $InstalledPacksTable> {
  $$InstalledPacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstalledPacksTableOrderingComposer
    extends Composer<_$AppDb, $InstalledPacksTable> {
  $$InstalledPacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstalledPacksTableAnnotationComposer
    extends Composer<_$AppDb, $InstalledPacksTable> {
  $$InstalledPacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );
}

class $$InstalledPacksTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $InstalledPacksTable,
          InstalledPack,
          $$InstalledPacksTableFilterComposer,
          $$InstalledPacksTableOrderingComposer,
          $$InstalledPacksTableAnnotationComposer,
          $$InstalledPacksTableCreateCompanionBuilder,
          $$InstalledPacksTableUpdateCompanionBuilder,
          (
            InstalledPack,
            BaseReferences<_$AppDb, $InstalledPacksTable, InstalledPack>,
          ),
          InstalledPack,
          PrefetchHooks Function()
        > {
  $$InstalledPacksTableTableManager(_$AppDb db, $InstalledPacksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstalledPacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstalledPacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstalledPacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> slug = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<int> installedAt = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstalledPacksCompanion(
                slug: slug,
                version: version,
                manifestJson: manifestJson,
                installedAt: installedAt,
                totalBytes: totalBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String slug,
                required int version,
                required String manifestJson,
                required int installedAt,
                required int totalBytes,
                Value<int> rowid = const Value.absent(),
              }) => InstalledPacksCompanion.insert(
                slug: slug,
                version: version,
                manifestJson: manifestJson,
                installedAt: installedAt,
                totalBytes: totalBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InstalledPacksTable, InstalledPack>(table),
                  BaseReferences<_$AppDb, $InstalledPacksTable, InstalledPack>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstalledPacksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $InstalledPacksTable,
      InstalledPack,
      $$InstalledPacksTableFilterComposer,
      $$InstalledPacksTableOrderingComposer,
      $$InstalledPacksTableAnnotationComposer,
      $$InstalledPacksTableCreateCompanionBuilder,
      $$InstalledPacksTableUpdateCompanionBuilder,
      (
        InstalledPack,
        BaseReferences<_$AppDb, $InstalledPacksTable, InstalledPack>,
      ),
      InstalledPack,
      PrefetchHooks Function()
    >;
typedef $$LocalTracksTableCreateCompanionBuilder =
    LocalTracksCompanion Function({
      required String packSlug,
      required int id,
      Value<String?> titleAm,
      Value<String?> titleLatin,
      Value<String?> artistAm,
      Value<String?> artistLatin,
      Value<int?> artistId,
      Value<int?> generationId,
      Value<int?> releaseYear,
      Value<String?> introPath,
      Value<String?> middlePath,
      Value<int> rowid,
    });
typedef $$LocalTracksTableUpdateCompanionBuilder =
    LocalTracksCompanion Function({
      Value<String> packSlug,
      Value<int> id,
      Value<String?> titleAm,
      Value<String?> titleLatin,
      Value<String?> artistAm,
      Value<String?> artistLatin,
      Value<int?> artistId,
      Value<int?> generationId,
      Value<int?> releaseYear,
      Value<String?> introPath,
      Value<String?> middlePath,
      Value<int> rowid,
    });

class $$LocalTracksTableFilterComposer
    extends Composer<_$AppDb, $LocalTracksTable> {
  $$LocalTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packSlug => $composableBuilder(
    column: $table.packSlug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleAm => $composableBuilder(
    column: $table.titleAm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleLatin => $composableBuilder(
    column: $table.titleLatin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistAm => $composableBuilder(
    column: $table.artistAm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistLatin => $composableBuilder(
    column: $table.artistLatin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get introPath => $composableBuilder(
    column: $table.introPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get middlePath => $composableBuilder(
    column: $table.middlePath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTracksTableOrderingComposer
    extends Composer<_$AppDb, $LocalTracksTable> {
  $$LocalTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packSlug => $composableBuilder(
    column: $table.packSlug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleAm => $composableBuilder(
    column: $table.titleAm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleLatin => $composableBuilder(
    column: $table.titleLatin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistAm => $composableBuilder(
    column: $table.artistAm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistLatin => $composableBuilder(
    column: $table.artistLatin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get artistId => $composableBuilder(
    column: $table.artistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get introPath => $composableBuilder(
    column: $table.introPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get middlePath => $composableBuilder(
    column: $table.middlePath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTracksTableAnnotationComposer
    extends Composer<_$AppDb, $LocalTracksTable> {
  $$LocalTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packSlug =>
      $composableBuilder(column: $table.packSlug, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get titleAm =>
      $composableBuilder(column: $table.titleAm, builder: (column) => column);

  GeneratedColumn<String> get titleLatin => $composableBuilder(
    column: $table.titleLatin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artistAm =>
      $composableBuilder(column: $table.artistAm, builder: (column) => column);

  GeneratedColumn<String> get artistLatin => $composableBuilder(
    column: $table.artistLatin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get artistId =>
      $composableBuilder(column: $table.artistId, builder: (column) => column);

  GeneratedColumn<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get releaseYear => $composableBuilder(
    column: $table.releaseYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get introPath =>
      $composableBuilder(column: $table.introPath, builder: (column) => column);

  GeneratedColumn<String> get middlePath => $composableBuilder(
    column: $table.middlePath,
    builder: (column) => column,
  );
}

class $$LocalTracksTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LocalTracksTable,
          LocalTrack,
          $$LocalTracksTableFilterComposer,
          $$LocalTracksTableOrderingComposer,
          $$LocalTracksTableAnnotationComposer,
          $$LocalTracksTableCreateCompanionBuilder,
          $$LocalTracksTableUpdateCompanionBuilder,
          (LocalTrack, BaseReferences<_$AppDb, $LocalTracksTable, LocalTrack>),
          LocalTrack,
          PrefetchHooks Function()
        > {
  $$LocalTracksTableTableManager(_$AppDb db, $LocalTracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> packSlug = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String?> titleAm = const Value.absent(),
                Value<String?> titleLatin = const Value.absent(),
                Value<String?> artistAm = const Value.absent(),
                Value<String?> artistLatin = const Value.absent(),
                Value<int?> artistId = const Value.absent(),
                Value<int?> generationId = const Value.absent(),
                Value<int?> releaseYear = const Value.absent(),
                Value<String?> introPath = const Value.absent(),
                Value<String?> middlePath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTracksCompanion(
                packSlug: packSlug,
                id: id,
                titleAm: titleAm,
                titleLatin: titleLatin,
                artistAm: artistAm,
                artistLatin: artistLatin,
                artistId: artistId,
                generationId: generationId,
                releaseYear: releaseYear,
                introPath: introPath,
                middlePath: middlePath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String packSlug,
                required int id,
                Value<String?> titleAm = const Value.absent(),
                Value<String?> titleLatin = const Value.absent(),
                Value<String?> artistAm = const Value.absent(),
                Value<String?> artistLatin = const Value.absent(),
                Value<int?> artistId = const Value.absent(),
                Value<int?> generationId = const Value.absent(),
                Value<int?> releaseYear = const Value.absent(),
                Value<String?> introPath = const Value.absent(),
                Value<String?> middlePath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTracksCompanion.insert(
                packSlug: packSlug,
                id: id,
                titleAm: titleAm,
                titleLatin: titleLatin,
                artistAm: artistAm,
                artistLatin: artistLatin,
                artistId: artistId,
                generationId: generationId,
                releaseYear: releaseYear,
                introPath: introPath,
                middlePath: middlePath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalTracksTable, LocalTrack>(table),
                  BaseReferences<_$AppDb, $LocalTracksTable, LocalTrack>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LocalTracksTable,
      LocalTrack,
      $$LocalTracksTableFilterComposer,
      $$LocalTracksTableOrderingComposer,
      $$LocalTracksTableAnnotationComposer,
      $$LocalTracksTableCreateCompanionBuilder,
      $$LocalTracksTableUpdateCompanionBuilder,
      (LocalTrack, BaseReferences<_$AppDb, $LocalTracksTable, LocalTrack>),
      LocalTrack,
      PrefetchHooks Function()
    >;
typedef $$PendingSessionsTableCreateCompanionBuilder =
    PendingSessionsCompanion Function({
      required String id,
      required String payloadJson,
      required int createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> nextAttemptAt,
      Value<bool> parked,
      Value<int> rowid,
    });
typedef $$PendingSessionsTableUpdateCompanionBuilder =
    PendingSessionsCompanion Function({
      Value<String> id,
      Value<String> payloadJson,
      Value<int> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> nextAttemptAt,
      Value<bool> parked,
      Value<int> rowid,
    });

class $$PendingSessionsTableFilterComposer
    extends Composer<_$AppDb, $PendingSessionsTable> {
  $$PendingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get parked => $composableBuilder(
    column: $table.parked,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingSessionsTableOrderingComposer
    extends Composer<_$AppDb, $PendingSessionsTable> {
  $$PendingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get parked => $composableBuilder(
    column: $table.parked,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingSessionsTableAnnotationComposer
    extends Composer<_$AppDb, $PendingSessionsTable> {
  $$PendingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get parked =>
      $composableBuilder(column: $table.parked, builder: (column) => column);
}

class $$PendingSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $PendingSessionsTable,
          PendingSession,
          $$PendingSessionsTableFilterComposer,
          $$PendingSessionsTableOrderingComposer,
          $$PendingSessionsTableAnnotationComposer,
          $$PendingSessionsTableCreateCompanionBuilder,
          $$PendingSessionsTableUpdateCompanionBuilder,
          (
            PendingSession,
            BaseReferences<_$AppDb, $PendingSessionsTable, PendingSession>,
          ),
          PendingSession,
          PrefetchHooks Function()
        > {
  $$PendingSessionsTableTableManager(_$AppDb db, $PendingSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<bool> parked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSessionsCompanion(
                id: id,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                nextAttemptAt: nextAttemptAt,
                parked: parked,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payloadJson,
                required int createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<bool> parked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSessionsCompanion.insert(
                id: id,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                nextAttemptAt: nextAttemptAt,
                parked: parked,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingSessionsTable, PendingSession>(table),
                  BaseReferences<
                    _$AppDb,
                    $PendingSessionsTable,
                    PendingSession
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $PendingSessionsTable,
      PendingSession,
      $$PendingSessionsTableFilterComposer,
      $$PendingSessionsTableOrderingComposer,
      $$PendingSessionsTableAnnotationComposer,
      $$PendingSessionsTableCreateCompanionBuilder,
      $$PendingSessionsTableUpdateCompanionBuilder,
      (
        PendingSession,
        BaseReferences<_$AppDb, $PendingSessionsTable, PendingSession>,
      ),
      PendingSession,
      PrefetchHooks Function()
    >;
typedef $$LocalBestsTableCreateCompanionBuilder = LocalBestsCompanion Function({
  required String mode,
  required int generationId,
  required int bestScore,
  required int achievedAt,
  Value<int> rowid,
});
typedef $$LocalBestsTableUpdateCompanionBuilder = LocalBestsCompanion Function({
  Value<String> mode,
  Value<int> generationId,
  Value<int> bestScore,
  Value<int> achievedAt,
  Value<int> rowid,
});

class $$LocalBestsTableFilterComposer
    extends Composer<_$AppDb, $LocalBestsTable> {
  $$LocalBestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bestScore => $composableBuilder(
    column: $table.bestScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get achievedAt => $composableBuilder(
    column: $table.achievedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalBestsTableOrderingComposer
    extends Composer<_$AppDb, $LocalBestsTable> {
  $$LocalBestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bestScore => $composableBuilder(
    column: $table.bestScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get achievedAt => $composableBuilder(
    column: $table.achievedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalBestsTableAnnotationComposer
    extends Composer<_$AppDb, $LocalBestsTable> {
  $$LocalBestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bestScore =>
      $composableBuilder(column: $table.bestScore, builder: (column) => column);

  GeneratedColumn<int> get achievedAt => $composableBuilder(
    column: $table.achievedAt,
    builder: (column) => column,
  );
}

class $$LocalBestsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LocalBestsTable,
          LocalBest,
          $$LocalBestsTableFilterComposer,
          $$LocalBestsTableOrderingComposer,
          $$LocalBestsTableAnnotationComposer,
          $$LocalBestsTableCreateCompanionBuilder,
          $$LocalBestsTableUpdateCompanionBuilder,
          (LocalBest, BaseReferences<_$AppDb, $LocalBestsTable, LocalBest>),
          LocalBest,
          PrefetchHooks Function()
        > {
  $$LocalBestsTableTableManager(_$AppDb db, $LocalBestsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalBestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalBestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalBestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mode = const Value.absent(),
                Value<int> generationId = const Value.absent(),
                Value<int> bestScore = const Value.absent(),
                Value<int> achievedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalBestsCompanion(
                mode: mode,
                generationId: generationId,
                bestScore: bestScore,
                achievedAt: achievedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mode,
                required int generationId,
                required int bestScore,
                required int achievedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalBestsCompanion.insert(
                mode: mode,
                generationId: generationId,
                bestScore: bestScore,
                achievedAt: achievedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalBestsTable, LocalBest>(table),
                  BaseReferences<_$AppDb, $LocalBestsTable, LocalBest>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalBestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LocalBestsTable,
      LocalBest,
      $$LocalBestsTableFilterComposer,
      $$LocalBestsTableOrderingComposer,
      $$LocalBestsTableAnnotationComposer,
      $$LocalBestsTableCreateCompanionBuilder,
      $$LocalBestsTableUpdateCompanionBuilder,
      (LocalBest, BaseReferences<_$AppDb, $LocalBestsTable, LocalBest>),
      LocalBest,
      PrefetchHooks Function()
    >;
typedef $$LocalCountersTableCreateCompanionBuilder =
    LocalCountersCompanion Function({
      required String name,
      Value<int> count,
      Value<int> rowid,
    });
typedef $$LocalCountersTableUpdateCompanionBuilder =
    LocalCountersCompanion Function({
      Value<String> name,
      Value<int> count,
      Value<int> rowid,
    });

class $$LocalCountersTableFilterComposer
    extends Composer<_$AppDb, $LocalCountersTable> {
  $$LocalCountersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCountersTableOrderingComposer
    extends Composer<_$AppDb, $LocalCountersTable> {
  $$LocalCountersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCountersTableAnnotationComposer
    extends Composer<_$AppDb, $LocalCountersTable> {
  $$LocalCountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);
}

class $$LocalCountersTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LocalCountersTable,
          LocalCounter,
          $$LocalCountersTableFilterComposer,
          $$LocalCountersTableOrderingComposer,
          $$LocalCountersTableAnnotationComposer,
          $$LocalCountersTableCreateCompanionBuilder,
          $$LocalCountersTableUpdateCompanionBuilder,
          (
            LocalCounter,
            BaseReferences<_$AppDb, $LocalCountersTable, LocalCounter>,
          ),
          LocalCounter,
          PrefetchHooks Function()
        > {
  $$LocalCountersTableTableManager(_$AppDb db, $LocalCountersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<int> count = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LocalCountersCompanion(name: name, count: count, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                Value<int> count = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCountersCompanion.insert(
                name: name,
                count: count,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalCountersTable, LocalCounter>(table),
                  BaseReferences<_$AppDb, $LocalCountersTable, LocalCounter>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCountersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LocalCountersTable,
      LocalCounter,
      $$LocalCountersTableFilterComposer,
      $$LocalCountersTableOrderingComposer,
      $$LocalCountersTableAnnotationComposer,
      $$LocalCountersTableCreateCompanionBuilder,
      $$LocalCountersTableUpdateCompanionBuilder,
      (
        LocalCounter,
        BaseReferences<_$AppDb, $LocalCountersTable, LocalCounter>,
      ),
      LocalCounter,
      PrefetchHooks Function()
    >;
typedef $$RecentSessionsTableCreateCompanionBuilder =
    RecentSessionsCompanion Function({
      required String sessionId,
      required int playedAt,
      required String trackIdsJson,
      Value<int?> serverScore,
      Value<int> rowid,
    });
typedef $$RecentSessionsTableUpdateCompanionBuilder =
    RecentSessionsCompanion Function({
      Value<String> sessionId,
      Value<int> playedAt,
      Value<String> trackIdsJson,
      Value<int?> serverScore,
      Value<int> rowid,
    });

class $$RecentSessionsTableFilterComposer
    extends Composer<_$AppDb, $RecentSessionsTable> {
  $$RecentSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackIdsJson => $composableBuilder(
    column: $table.trackIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverScore => $composableBuilder(
    column: $table.serverScore,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentSessionsTableOrderingComposer
    extends Composer<_$AppDb, $RecentSessionsTable> {
  $$RecentSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackIdsJson => $composableBuilder(
    column: $table.trackIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverScore => $composableBuilder(
    column: $table.serverScore,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentSessionsTableAnnotationComposer
    extends Composer<_$AppDb, $RecentSessionsTable> {
  $$RecentSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  GeneratedColumn<String> get trackIdsJson => $composableBuilder(
    column: $table.trackIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverScore => $composableBuilder(
    column: $table.serverScore,
    builder: (column) => column,
  );
}

class $$RecentSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $RecentSessionsTable,
          RecentSession,
          $$RecentSessionsTableFilterComposer,
          $$RecentSessionsTableOrderingComposer,
          $$RecentSessionsTableAnnotationComposer,
          $$RecentSessionsTableCreateCompanionBuilder,
          $$RecentSessionsTableUpdateCompanionBuilder,
          (
            RecentSession,
            BaseReferences<_$AppDb, $RecentSessionsTable, RecentSession>,
          ),
          RecentSession,
          PrefetchHooks Function()
        > {
  $$RecentSessionsTableTableManager(_$AppDb db, $RecentSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> playedAt = const Value.absent(),
                Value<String> trackIdsJson = const Value.absent(),
                Value<int?> serverScore = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecentSessionsCompanion(
                sessionId: sessionId,
                playedAt: playedAt,
                trackIdsJson: trackIdsJson,
                serverScore: serverScore,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int playedAt,
                required String trackIdsJson,
                Value<int?> serverScore = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecentSessionsCompanion.insert(
                sessionId: sessionId,
                playedAt: playedAt,
                trackIdsJson: trackIdsJson,
                serverScore: serverScore,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecentSessionsTable, RecentSession>(table),
                  BaseReferences<_$AppDb, $RecentSessionsTable, RecentSession>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $RecentSessionsTable,
      RecentSession,
      $$RecentSessionsTableFilterComposer,
      $$RecentSessionsTableOrderingComposer,
      $$RecentSessionsTableAnnotationComposer,
      $$RecentSessionsTableCreateCompanionBuilder,
      $$RecentSessionsTableUpdateCompanionBuilder,
      (
        RecentSession,
        BaseReferences<_$AppDb, $RecentSessionsTable, RecentSession>,
      ),
      RecentSession,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$InstalledPacksTableTableManager get installedPacks =>
      $$InstalledPacksTableTableManager(_db, _db.installedPacks);
  $$LocalTracksTableTableManager get localTracks =>
      $$LocalTracksTableTableManager(_db, _db.localTracks);
  $$PendingSessionsTableTableManager get pendingSessions =>
      $$PendingSessionsTableTableManager(_db, _db.pendingSessions);
  $$LocalBestsTableTableManager get localBests =>
      $$LocalBestsTableTableManager(_db, _db.localBests);
  $$LocalCountersTableTableManager get localCounters =>
      $$LocalCountersTableTableManager(_db, _db.localCounters);
  $$RecentSessionsTableTableManager get recentSessions =>
      $$RecentSessionsTableTableManager(_db, _db.recentSessions);
}
