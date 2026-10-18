import 'dart:io';

import 'package:crypto/crypto.dart';

/// Whether [file] hashes to [expectedSha256] (lowercase hex).
Future<bool> fileHasSha256(File file, String expectedSha256) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == expectedSha256;
}
