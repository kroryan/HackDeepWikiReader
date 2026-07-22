import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackdeepwikireader/zim/zim_archive.dart';
import 'package:hackdeepwikireader/zim/zim_local_server.dart';

void main() {
  late Directory tempDir;
  late File zimFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hdwr_zim_test');
    zimFile = File('${tempDir.path}/mini.zim');
    await zimFile.writeAsBytes(_buildMiniZim(), flush: true);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'parses metadata, main redirect, assets, and literal percent paths',
    () async {
      final archive = await ZimArchive.open(zimFile.path);
      addTearDown(archive.close);

      expect(archive.entryCount, 5);
      expect(await archive.getMetadataString('Title'), 'Mini ZIM');
      expect(await archive.mainPagePath(), 'index');
      expect(await archive.resolveEntryPath('home'), 'index');

      final redirected = await archive.getEntryContent('home');
      expect(redirected?.mimetype, 'text/html');
      expect(utf8.decode(redirected!.bytes), contains('<h1>Mini</h1>'));

      final image = await archive.getEntryContent('assets/a%2Cb.png');
      expect(image?.mimetype, 'image/png');
      expect(image?.bytes, orderedEquals(<int>[137, 80, 78, 71]));
    },
  );

  test(
    'loopback server serves browser-safe MIME, CSP, and real redirects',
    () async {
      final archive = await ZimArchive.open(zimFile.path);
      final server = ZimLocalServer(archive);
      final client = HttpClient();
      await server.start();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await archive.close();
      });

      final encodedImageUrl = server.urlForPath('assets/a%2Cb.png');
      expect(encodedImageUrl.path, '/assets/a%252Cb.png');
      final imageResponse = await (await client.getUrl(
        encodedImageUrl,
      )).close();
      expect(imageResponse.statusCode, HttpStatus.ok);
      expect(imageResponse.headers.contentType?.mimeType, 'image/png');
      expect(
        await imageResponse.fold<List<int>>(
          <int>[],
          (out, bytes) => out..addAll(bytes),
        ),
        orderedEquals(<int>[137, 80, 78, 71]),
      );

      final pageResponse = await (await client.getUrl(
        server.urlForPath('index'),
      )).close();
      expect(pageResponse.statusCode, HttpStatus.ok);
      expect(pageResponse.headers.contentType?.mimeType, 'text/html');
      expect(
        pageResponse.headers.value('content-security-policy'),
        contains("script-src 'none'"),
      );
      await pageResponse.drain<void>();

      final redirectRequest = await client.getUrl(server.urlForPath('home'));
      redirectRequest.followRedirects = false;
      final redirectResponse = await redirectRequest.close();
      expect(redirectResponse.statusCode, HttpStatus.temporaryRedirect);
      expect(
        redirectResponse.headers.value(HttpHeaders.locationHeader),
        server.urlForPath('index').toString(),
      );
      await redirectResponse.drain<void>();
    },
  );

  test('rejects a file without the ZIM magic header', () async {
    final invalid = File('${tempDir.path}/invalid.zim');
    await invalid.writeAsBytes(List<int>.filled(80, 0));
    expect(
      () => ZimArchive.open(invalid.path),
      throwsA(isA<FormatException>()),
    );
  });
}

Uint8List _buildMiniZim() {
  final title = utf8.encode('Mini ZIM');
  final html = utf8.encode(
    '<html><head><link rel="stylesheet" href="style.css"></head>'
    '<body><h1>Mini</h1><img src="assets/a%252Cb.png"></body></html>',
  );
  final css = utf8.encode('body{display:grid;color:#123456}');
  final png = <int>[137, 80, 78, 71];
  final blobs = <List<int>>[title, html, css, png];

  final mimeBytes = utf8.encode(
    'text/html\u0000text/css\u0000image/png\u0000text/plain\u0000\u0000',
  );
  final dirents = <Uint8List>[
    _contentDirent(mimetype: 3, blob: 0, path: 'Title'),
    _contentDirent(mimetype: 0, blob: 1, path: 'index', title: 'Home'),
    _contentDirent(mimetype: 1, blob: 2, path: 'style.css'),
    _contentDirent(mimetype: 2, blob: 3, path: 'assets/a%2Cb.png'),
    _redirectDirent(targetIndex: 1, path: 'home'),
  ];

  const headerLength = 80;
  final mimeListPos = headerLength;
  var cursor = mimeListPos + mimeBytes.length;
  final urlPointers = <int>[];
  for (final dirent in dirents) {
    urlPointers.add(cursor);
    cursor += dirent.length;
  }
  final urlPtrPos = cursor;
  final clusterPtrPos = urlPtrPos + dirents.length * 8;
  final clusterStart = clusterPtrPos + 8;

  final clusterPayload = BytesBuilder(copy: false);
  final firstBlobOffset = (blobs.length + 1) * 4;
  var blobOffset = firstBlobOffset;
  final offsets = <int>[blobOffset];
  for (final blob in blobs) {
    blobOffset += blob.length;
    offsets.add(blobOffset);
  }
  final offsetBytes = ByteData(offsets.length * 4);
  for (var i = 0; i < offsets.length; i++) {
    offsetBytes.setUint32(i * 4, offsets[i], Endian.little);
  }
  clusterPayload.add(offsetBytes.buffer.asUint8List());
  for (final blob in blobs) {
    clusterPayload.add(blob);
  }
  final cluster = Uint8List.fromList(<int>[1, ...clusterPayload.takeBytes()]);

  final header = ByteData(headerLength)
    ..setUint32(0, 0x044d495a, Endian.little)
    ..setUint16(4, 6, Endian.little)
    ..setUint16(6, 1, Endian.little)
    ..setUint32(24, dirents.length, Endian.little)
    ..setUint32(28, 1, Endian.little)
    ..setUint64(32, urlPtrPos, Endian.little)
    ..setUint64(40, 0xffffffffffffffff, Endian.little)
    ..setUint64(48, clusterPtrPos, Endian.little)
    ..setUint64(56, mimeListPos, Endian.little)
    ..setUint32(64, 4, Endian.little)
    ..setUint32(68, 0xffffffff, Endian.little)
    ..setUint64(72, 0, Endian.little);

  final output = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(mimeBytes);
  for (final dirent in dirents) {
    output.add(dirent);
  }
  final urlPointerBytes = ByteData(dirents.length * 8);
  for (var i = 0; i < urlPointers.length; i++) {
    urlPointerBytes.setUint64(i * 8, urlPointers[i], Endian.little);
  }
  output
    ..add(urlPointerBytes.buffer.asUint8List())
    ..add(
      (ByteData(
        8,
      )..setUint64(0, clusterStart, Endian.little)).buffer.asUint8List(),
    )
    ..add(cluster);
  return output.takeBytes();
}

Uint8List _contentDirent({
  required int mimetype,
  required int blob,
  required String path,
  String title = '',
}) {
  final fixed = ByteData(16)
    ..setUint16(0, mimetype, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, 0, Endian.little)
    ..setUint32(12, blob, Endian.little);
  return Uint8List.fromList(<int>[
    ...fixed.buffer.asUint8List(),
    ...utf8.encode(path),
    0,
    ...utf8.encode(title),
    0,
  ]);
}

Uint8List _redirectDirent({required int targetIndex, required String path}) {
  final fixed = ByteData(12)
    ..setUint16(0, 0xffff, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, targetIndex, Endian.little);
  return Uint8List.fromList(<int>[
    ...fixed.buffer.asUint8List(),
    ...utf8.encode(path),
    0,
    0,
  ]);
}
