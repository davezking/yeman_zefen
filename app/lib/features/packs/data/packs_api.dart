import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/http/api_client.dart';

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

/// Lists packs through the authenticated [ApiClient] and fetches manifests
/// from the CDN with a plain client: the ID token goes only to the API.
class PacksApi {
  PacksApi({required this.api, http.Client? cdnClient}) : _cdn = cdnClient ?? http.Client();

  final ApiClient api;
  final http.Client _cdn;

  static const _timeout = Duration(seconds: 15);

  /// Throws [ApiException] when the API call fails.
  Future<List<PackListing>> listPacks() async {
    final body = await api.getJson('/v1/packs') as Map<String, dynamic>;
    return [
      for (final p in body['packs'] as List<dynamic>) PackListing.fromJson(p as Map<String, dynamic>),
    ];
  }

  /// Returns the raw manifest text, so the exact bytes that were verified are what gets stored.
  Future<String> fetchManifestJson(String manifestUrl) async {
    final uri = Uri.parse(manifestUrl);
    final res = await _cdn.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw PacksApiException('GET $uri returned ${res.statusCode}');
    }
    return utf8.decode(res.bodyBytes);
  }

  void closeCdn() => _cdn.close();
}
