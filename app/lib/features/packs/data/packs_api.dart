import 'dart:convert';

import 'package:http/http.dart' as http;

class PackListing {
  const PackListing({
    required this.slug,
    required this.nameAm,
    required this.nameEn,
    required this.version,
    required this.manifestUrl,
    required this.trackCount,
    required this.totalBytes,
    required this.publishedAt,
  });

  final String slug;
  final String nameAm;
  final String nameEn;
  final int version;
  final String manifestUrl;
  final int trackCount;
  final int totalBytes;
  final int publishedAt;

  factory PackListing.fromJson(Map<String, dynamic> json) {
    final names = json['names'] as Map<String, dynamic>;
    return PackListing(
      slug: json['slug'] as String,
      nameAm: names['am'] as String,
      nameEn: names['en'] as String,
      version: json['version'] as int,
      manifestUrl: json['manifestUrl'] as String,
      trackCount: json['trackCount'] as int,
      totalBytes: json['totalBytes'] as int,
      publishedAt: json['publishedAt'] as int,
    );
  }
}

class PacksApiException implements Exception {
  const PacksApiException(this.message);
  final String message;

  @override
  String toString() => 'PacksApiException: $message';
}

/// Talks to the public pack endpoints of the API Worker and the CDN.
class PacksApi {
  PacksApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Future<List<PackListing>> listPacks() async {
    final body = await _get(Uri.parse('$baseUrl/v1/packs'));
    final packs = (jsonDecode(body) as Map<String, dynamic>)['packs'] as List<dynamic>;
    return [
      for (final p in packs) PackListing.fromJson(p as Map<String, dynamic>),
    ];
  }

  /// Returns the raw manifest text, so the exact bytes that were verified are what gets stored.
  Future<String> fetchManifestJson(String manifestUrl) =>
      _get(Uri.parse(manifestUrl));

  Future<String> _get(Uri uri) async {
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw PacksApiException('GET $uri returned ${res.statusCode}');
    }
    return utf8.decode(res.bodyBytes);
  }

  void close() => _client.close();
}
