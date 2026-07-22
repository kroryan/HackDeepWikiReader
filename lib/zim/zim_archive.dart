import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show XZDecoder;

import '../native/zstd_native.dart';
import 'zim_format.dart';

class ZimEntryContent {
  final Uint8List bytes;
  final String mimetype;
  const ZimEntryContent(this.bytes, this.mimetype);
}

/// A parsed, browsable summary of one directory entry -- everything needed
/// to list/search/navigate the archive without decompressing any content.
class ZimEntrySummary {
  final String path;
  final String title;
  final String mimetype;
  final bool isRedirect;

  const ZimEntrySummary({
    required this.path,
    required this.title,
    required this.mimetype,
    required this.isRedirect,
  });
}

/// Random-access byte source abstraction -- lets ZimArchive's parsing logic
/// stay identical whether the archive is held fully in memory (fast: one
/// bulk read, then pure byte-slicing for tens of thousands of directory
/// entries with no further I/O) or streamed off disk a window at a time
/// (bounded memory, for archives too big to hold in RAM). See
/// [ZimArchive.open] for which one gets picked and why.
abstract class _ByteSource {
  Future<Uint8List> readAt(int offset, int length);
  Future<int> length();
  Future<void> close();
}

class _MemoryByteSource implements _ByteSource {
  final Uint8List _data;
  _MemoryByteSource(this._data);

  @override
  Future<Uint8List> readAt(int offset, int len) async {
    final end = (offset + len) > _data.length ? _data.length : offset + len;
    if (offset >= _data.length) return Uint8List(0);
    return Uint8List.sublistView(_data, offset, end);
  }

  @override
  Future<int> length() async => _data.length;

  @override
  Future<void> close() async {}
}

class _FileByteSource implements _ByteSource {
  final RandomAccessFile _file;
  Future<void> _pending = Future<void>.value();
  bool _closed = false;
  _FileByteSource(this._file);

  @override
  Future<Uint8List> readAt(int offset, int len) {
    if (_closed) return Future.error(StateError('ZIM archive is closed'));

    // RandomAccessFile has one shared cursor and rejects overlapping async
    // operations. A real page commonly requests several images/fonts at the
    // same time, so serialize seek+read as one operation. Without this queue,
    // large archives (which use the disk-backed source) intermittently return
    // corrupt assets or "an async operation is currently pending".
    final result = Completer<Uint8List>();
    _pending = _pending.then((_) async {
      try {
        await _file.setPosition(offset);
        result.complete(await _file.read(len));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<int> length() => _file.length();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pending;
    await _file.close();
  }
}

/// Reads a .zim archive directly off disk -- fully offline, no server
/// involved (see openzim.org/wiki/ZIM_file_format). Every entry's content
/// (HTML pages, CSS, images, ...) is decompressed lazily and on demand.
/// Directory metadata (path/title/mimetype index per entry -- not content)
/// is scanned once, up front: for archives under [_inMemoryThreshold] this
/// happens against an in-memory copy of the whole file, which turns tens of
/// thousands of directory-entry reads from that many slow async syscall
/// round-trips into pure in-process byte slicing (verified against a real
/// 186MB/56k-entry Wikipedia .zim: multiple seconds -> under a second).
/// Larger archives fall back to streaming reads off disk, bounded in memory
/// but slower to index. Clusters (the compressed blocks entries' content
/// lives in) are cached after first decompression -- browsing between
/// entries that share a cluster (common: consecutive articles are usually
/// clustered together) doesn't redundantly decompress.
class ZimArchive {
  static const _inMemoryThreshold = 300 * 1024 * 1024; // 300MB

  final _ByteSource _source;
  final ZimHeader header;
  final List<String> _mimetypes;
  final List<int> _urlPtrs;
  final Map<int, _DecodedCluster> _clusterCache = {};
  final List<int> _clusterCacheOrder = [];
  static const _maxCachedClusters = 12;

  String? _mainPagePath;
  bool _mainPageResolved = false;

  ZimArchive._(this._source, this.header, this._mimetypes, this._urlPtrs);

  static Future<ZimArchive> open(String path) async {
    final fileLength = await File(path).length();
    final _ByteSource source;
    if (fileLength <= _inMemoryThreshold) {
      source = _MemoryByteSource(await File(path).readAsBytes());
    } else {
      source = _FileByteSource(await File(path).open(mode: FileMode.read));
    }
    final header = await _readHeader(source);
    final mimetypes = await _readMimetypes(source, header.mimeListPos);
    final urlPtrs = await _readUrlPointerList(
      source,
      header.urlPtrPos,
      header.entryCount,
    );
    return ZimArchive._(source, header, mimetypes, urlPtrs);
  }

  Future<void> close() => _source.close();

  int get entryCount => header.entryCount;

  static Future<ZimHeader> _readHeader(_ByteSource f) async {
    final bytes = await f.readAt(0, 80);
    if (bytes.length < 80) {
      throw const FormatException('ZIM header is truncated');
    }
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != 0x044d495a) {
      throw const FormatException('Not a ZIM archive (invalid magic number)');
    }
    return ZimHeader(
      majorVersion: bd.getUint16(4, Endian.little),
      minorVersion: bd.getUint16(6, Endian.little),
      entryCount: bd.getUint32(24, Endian.little),
      clusterCount: bd.getUint32(28, Endian.little),
      urlPtrPos: bd.getUint64(32, Endian.little),
      titlePtrPos: bd.getUint64(40, Endian.little),
      clusterPtrPos: bd.getUint64(48, Endian.little),
      mimeListPos: bd.getUint64(56, Endian.little),
      checksumPos: bd.getUint64(72, Endian.little),
      mainPage: bd.getUint32(64, Endian.little),
    );
  }

  static Future<List<String>> _readMimetypes(
    _ByteSource f,
    int mimeListPos,
  ) async {
    // Null-terminated UTF-8 strings, terminated by one empty string. Read a
    // generous chunk up front (mimetype lists are always tiny -- a couple
    // dozen bytes per real-world entry type) instead of byte-by-byte reads.
    final chunk = await f.readAt(mimeListPos, 4096);
    final mimes = <String>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0) {
        if (i == start) break; // empty string -> end of list
        mimes.add(utf8.decode(chunk.sublist(start, i)));
        start = i + 1;
      }
    }
    return mimes;
  }

  static Future<List<int>> _readUrlPointerList(
    _ByteSource f,
    int urlPtrPos,
    int count,
  ) async {
    final bytes = await f.readAt(urlPtrPos, count * 8);
    final bd = ByteData.sublistView(bytes);
    return List<int>.generate(count, (i) => bd.getUint64(i * 8, Endian.little));
  }

  Future<ZimDirentInfo> _readDirent(int entryIndex) async {
    final offset = _urlPtrs[entryIndex];
    // The fixed header is at most 16 bytes; url+title are almost always
    // well under this window -- retry with a bigger read in the rare case
    // a title/url is unusually long.
    var window = 512;
    while (true) {
      final chunk = await _source.readAt(offset, window);
      final parsed = _tryParseDirent(entryIndex, chunk);
      if (parsed != null) return parsed;
      if (window > 1 << 20) {
        throw const FormatException(
          'ZIM directory entry has no terminating null byte (corrupt archive?)',
        );
      }
      window *= 4;
    }
  }

  ZimDirentInfo? _tryParseDirent(int entryIndex, Uint8List chunk) {
    if (chunk.length < 4) return null;
    final bd = ByteData.sublistView(chunk);
    final mimetypeIndex = bd.getUint16(0, Endian.little);
    final isRedirect = mimetypeIndex == zimRedirectMimetype;
    final fixedLen = isRedirect ? 12 : 16;
    if (chunk.length < fixedLen) return null;
    final cluster = isRedirect ? 0 : bd.getUint32(8, Endian.little);
    final blob = isRedirect ? 0 : bd.getUint32(12, Endian.little);
    final redirectIndex = isRedirect ? bd.getUint32(8, Endian.little) : 0;

    var pos = fixedLen;
    final urlEnd = chunk.indexOf(0, pos);
    if (urlEnd == -1) return null;
    final url = utf8.decode(chunk.sublist(pos, urlEnd), allowMalformed: true);
    pos = urlEnd + 1;
    final titleEnd = chunk.indexOf(0, pos);
    if (titleEnd == -1) return null;
    final title = utf8.decode(
      chunk.sublist(pos, titleEnd),
      allowMalformed: true,
    );

    return ZimDirentInfo(
      index: entryIndex,
      mimetypeIndex: mimetypeIndex,
      isRedirect: isRedirect,
      cluster: cluster,
      blob: blob,
      redirectIndex: redirectIndex,
      url: url,
      title: title,
    );
  }

  String mimetypeFor(ZimDirentInfo d) {
    if (d.isRedirect ||
        d.mimetypeIndex < 0 ||
        d.mimetypeIndex >= _mimetypes.length) {
      return '';
    }
    return _mimetypes[d.mimetypeIndex];
  }

  Map<String, ZimDirentInfo>? _byPath;
  List<ZimDirentInfo>? _allDirents;

  /// Scans every directory entry once (path/title/mimetype/cluster/blob --
  /// no content) and caches the result by path, so later lookups
  /// (getEntryContent, metadata reads, listEntries) are O(1) map hits
  /// instead of re-reading the whole directory from disk every time.
  /// Entries are stored URL-sorted, but replicating that ordering via
  /// binary search (grouped by an internal namespace flag, not a plain
  /// string sort -- verified against test.zim) is riskier than it's worth
  /// for archives in this app's realistic size range; scanning once and
  /// caching is simpler and correct.
  Future<List<ZimDirentInfo>> _ensureIndex() async {
    final cached = _allDirents;
    if (cached != null) return cached;
    final all = <ZimDirentInfo>[];
    final byPath = <String, ZimDirentInfo>{};
    for (var i = 0; i < header.entryCount; i++) {
      final d = await _readDirent(i);
      all.add(d);
      byPath[d.url] = d;
    }
    _allDirents = all;
    _byPath = byPath;
    return all;
  }

  /// The browsable index -- path/title/mimetype for every entry. Namespace-
  /// only entries some archives ship (metadata keys, the Xapian/title
  /// search indexes, listing files) are filtered out by the caller based on
  /// mimetype/path, not here.
  Future<List<ZimEntrySummary>> listEntries() async {
    final all = await _ensureIndex();
    return [
      for (final d in all)
        ZimEntrySummary(
          path: d.url,
          title: d.displayTitle,
          mimetype: mimetypeFor(d),
          isRedirect: d.isRedirect,
        ),
    ];
  }

  /// Resolves the archive's main/landing page path, following the one
  /// redirect hop main entries always are (see openzim.org: the main entry
  /// itself has no independently-resolvable path -- only its redirect
  /// target does).
  Future<String?> mainPagePath() async {
    if (_mainPageResolved) return _mainPagePath;
    _mainPageResolved = true;
    if (!header.hasMainPage || header.mainPage >= header.entryCount) {
      return null;
    }
    final d = await _resolveDirentByIndex(header.mainPage);
    _mainPagePath = d?.url;
    return _mainPagePath;
  }

  Future<ZimDirentInfo?> _findByPath(String path) async {
    await _ensureIndex();
    return _byPath![path];
  }

  Future<ZimDirentInfo?> _resolveDirentByIndex(int entryIndex) async {
    final seen = <int>{};
    var index = entryIndex;
    while (index >= 0 && index < header.entryCount && seen.add(index)) {
      final d = await _readDirent(index);
      if (!d.isRedirect) return d;
      index = d.redirectIndex;
    }
    return null;
  }

  Future<ZimDirentInfo?> _resolveDirent(String path) async {
    final first = await _findByPath(path);
    if (first == null) return null;
    return first.isRedirect
        ? _resolveDirentByIndex(first.redirectIndex)
        : first;
  }

  /// Returns the real content entry behind [path]. The local HTTP server uses
  /// this to emit an actual HTTP redirect, preserving the target entry's
  /// directory as the browser base URL for relative images/stylesheets.
  Future<String?> resolveEntryPath(String path) async =>
      (await _resolveDirent(path))?.url;

  /// Convenience for reading a small metadata entry (Title, Description,
  /// ...) as text -- these are regular content entries at a plain path, no
  /// special namespace handling needed.
  Future<String?> getMetadataString(String key) async {
    final content = await getEntryContent(key);
    if (content == null) return null;
    return utf8.decode(content.bytes, allowMalformed: true);
  }

  /// Fetches an entry's content by path, following one redirect hop if
  /// needed, decompressing its cluster (cached) and slicing out its blob.
  Future<ZimEntryContent?> getEntryContent(String path) async {
    final d = await _resolveDirent(path);
    if (d == null) return null;
    final cluster = await _readCluster(d.cluster);
    final blobs = _splitBlobs(cluster.data, cluster.extended);
    if (d.blob + 1 >= blobs.length) return null;
    final bytes = cluster.data.sublist(blobs[d.blob], blobs[d.blob + 1]);
    var mimetype = mimetypeFor(d);
    if (mimetype.isEmpty || mimetype == 'application/octet-stream') {
      final guessed = _guessMimetypeFromPath(d.url);
      if (guessed != null) mimetype = guessed;
    }
    return ZimEntryContent(Uint8List.fromList(bytes), mimetype);
  }

  String? _guessMimetypeFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return null;
    switch (path.substring(dot + 1).toLowerCase()) {
      case 'css':
        return 'text/css';
      case 'js':
        return 'application/javascript';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'avif':
        return 'image/avif';
      case 'ico':
        return 'image/x-icon';
      case 'bmp':
        return 'image/bmp';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      case 'ttf':
        return 'font/ttf';
      case 'otf':
        return 'font/otf';
      case 'xml':
        return 'application/xml';
      case 'json':
        return 'application/json';
      case 'pdf':
        return 'application/pdf';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
        return 'audio/ogg';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      default:
        return null;
    }
  }

  Future<_DecodedCluster> _readCluster(int clusterIndex) async {
    final cached = _clusterCache[clusterIndex];
    if (cached != null) return cached;

    final start = await _clusterStart(clusterIndex);
    int end;
    if (clusterIndex + 1 < header.clusterCount) {
      end = await _clusterStart(clusterIndex + 1);
    } else {
      // Last cluster: its end is wherever the next section physically
      // starts, but the spec doesn't fix which section that is (sections
      // aren't guaranteed to be laid out in a particular order) -- take the
      // closest known offset after `start`, falling back to EOF.
      final fileLen = await _source.length();
      end = fileLen;
      for (final candidate in [...header.knownSectionOffsets, fileLen]) {
        if (candidate > start && candidate < end) end = candidate;
      }
    }

    final raw = await _source.readAt(start, end - start);
    final compressionByte = raw[0] & 0x0f;
    final extended = (raw[0] & 0x10) != 0;
    final payload = raw.sublist(1);

    final Uint8List decompressed;
    switch (compressionByte) {
      case ZimCompression.none1:
      case ZimCompression.none2:
        decompressed = payload;
        break;
      case ZimCompression.zstd:
        decompressed = zstdDecompress(payload);
        break;
      case ZimCompression.lzma2:
        decompressed = Uint8List.fromList(
          XZDecoder().decodeBytes(payload, verify: false),
        );
        break;
      default:
        throw FormatException(
          'Unsupported ZIM cluster compression type $compressionByte',
        );
    }

    final result = _DecodedCluster(decompressed, extended);
    _clusterCache[clusterIndex] = result;
    _clusterCacheOrder.add(clusterIndex);
    if (_clusterCacheOrder.length > _maxCachedClusters) {
      _clusterCache.remove(_clusterCacheOrder.removeAt(0));
    }
    return result;
  }

  Future<int> _clusterStart(int clusterIndex) async {
    final bytes = await _source.readAt(
      header.clusterPtrPos + clusterIndex * 8,
      8,
    );
    return ByteData.sublistView(bytes).getUint64(0, Endian.little);
  }

  /// Splits a decompressed cluster into blob byte-ranges. The cluster's own
  /// blob-pointer list gives absolute offsets *within the cluster*
  /// (offset[0] always equals the pointer list's own byte length) --
  /// verified against test.zim: offset[0]=200 for a 49-blob cluster (50
  /// pointers * 4 bytes), and slicing by these offsets reproduces libzim's
  /// content byte-for-byte. Offsets are 8 bytes instead of 4 in "extended"
  /// clusters (used once a cluster's total size needs more than 32 bits).
  List<int> _splitBlobs(Uint8List cluster, bool extended) {
    final bd = ByteData.sublistView(cluster);
    final width = extended ? 8 : 4;
    final firstOffset = extended
        ? bd.getUint64(0, Endian.little)
        : bd.getUint32(0, Endian.little);
    final numOffsets = firstOffset ~/ width;
    return List<int>.generate(
      numOffsets,
      (i) => extended
          ? bd.getUint64(i * 8, Endian.little)
          : bd.getUint32(i * 4, Endian.little),
    );
  }
}

class _DecodedCluster {
  final Uint8List data;
  final bool extended;
  const _DecodedCluster(this.data, this.extended);
}
