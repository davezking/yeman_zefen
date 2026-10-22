import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/features/packs/data/clip_downloader.dart';

void main() {
  late Directory base;

  setUp(() async => base = await Directory.systemTemp.createTemp('clip_downloader_test'));
  tearDown(() async => base.delete(recursive: true));

  HttpClipDownloader downloader(MockClient client) =>
      HttpClipDownloader(supportDirectory: () async => base, client: client);

  test('saves the clip at its path under the support directory and reports progress', () async {
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final progress = <double>[];
    await downloader(MockClient((request) async {
      expect(request.url.toString(), 'https://cdn.test/clips/1.m4a');
      return http.Response.bytes(bytes, 200);
    })).download(url: 'https://cdn.test/clips/1.m4a', relativePath: 'clips/stream/1_intro.m4a', onProgress: progress.add);

    final file = File(p.join(base.path, 'clips/stream/1_intro.m4a'));
    expect(await file.readAsBytes(), bytes);
    expect(progress.last, 1.0);
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test('a failed request throws and leaves no file', () async {
    final call = downloader(MockClient((_) async => http.Response('gone', 404)))
        .download(url: 'https://cdn.test/clips/2.m4a', relativePath: 'clips/stream/2_intro.m4a', onProgress: (_) {});
    await expectLater(call, throwsA(isA<ClipDownloadException>()));
    expect(await File(p.join(base.path, 'clips/stream/2_intro.m4a')).exists(), isFalse);
    expect(await File(p.join(base.path, 'clips/stream/2_intro.m4a.part')).exists(), isFalse);
  });

  test('a network error throws a ClipDownloadException', () async {
    final call = downloader(MockClient((_) async => throw const SocketException('offline')))
        .download(url: 'https://cdn.test/clips/3.m4a', relativePath: 'clips/stream/3_intro.m4a', onProgress: (_) {});
    await expectLater(call, throwsA(isA<ClipDownloadException>()));
  });
}
