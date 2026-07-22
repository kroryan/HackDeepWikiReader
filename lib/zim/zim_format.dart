/// Low-level ZIM binary format constants and structs -- see
/// https://openzim.org/wiki/ZIM_file_format. Every offset/field below was
/// validated byte-for-byte against tmp/zim_samples/test.zim (cross-checked
/// against openZIM's own libzim Python bindings) before being relied on by
/// zim_archive.dart -- this is a from-scratch reimplementation (no
/// pure-Dart ZIM/zstd library exists), so getting these exactly right
/// matters more than usual.
library;

/// mimetype value marking a directory entry as a redirect (its "cluster/blob"
/// fields are replaced by a single "redirect index" instead).
const zimRedirectMimetype = 0xffff;

/// Cluster compression-type byte (low 4 bits; bit 4 is the "extended"
/// flag -- blob offsets are 8 bytes instead of 4, used for very large
/// clusters). Values 2/3 (zlib/bzip2) existed in ancient ZIM files and are
/// deliberately unsupported here -- no archive still in circulation uses them.
class ZimCompression {
  static const none1 = 0; // legacy "no compression"
  static const none2 = 1; // no compression
  static const lzma2 = 4;
  static const zstd = 5;
}

class ZimHeader {
  final int majorVersion;
  final int minorVersion;
  final int entryCount; // total directory entries (articleCount field)
  final int clusterCount;
  final int urlPtrPos;
  final int titlePtrPos;
  final int clusterPtrPos;
  final int mimeListPos;
  final int checksumPos;
  final int mainPage; // 0xffffffff if none

  const ZimHeader({
    required this.majorVersion,
    required this.minorVersion,
    required this.entryCount,
    required this.clusterCount,
    required this.urlPtrPos,
    required this.titlePtrPos,
    required this.clusterPtrPos,
    required this.mimeListPos,
    required this.checksumPos,
    required this.mainPage,
  });

  bool get hasMainPage => mainPage != 0xffffffff;

  /// All section-start offsets the spec defines, used to find whatever
  /// section physically follows the cluster data -- the spec doesn't
  /// mandate a fixed physical ordering of sections (verified: in
  /// test.zim, clusters sit *before* the URL pointer list, not after).
  List<int> get knownSectionOffsets {
    const noTitleIndex = 0xFFFFFFFFFFFFFFFF;
    return [
      mimeListPos,
      urlPtrPos,
      if (titlePtrPos != noTitleIndex) titlePtrPos,
      clusterPtrPos,
      if (checksumPos != 0) checksumPos,
    ];
  }
}

/// One parsed Directory Entry -- either a content entry (mimetype/cluster/
/// blob point at real data) or a redirect (redirectIndex points at another
/// entry's position in the URL pointer list).
class ZimDirentInfo {
  final int index; // position in the URL pointer list ("entry id")
  final int mimetypeIndex;
  final bool isRedirect;
  final int cluster;
  final int blob;
  final int redirectIndex;
  final String url;
  final String title;

  const ZimDirentInfo({
    required this.index,
    required this.mimetypeIndex,
    required this.isRedirect,
    required this.cluster,
    required this.blob,
    required this.redirectIndex,
    required this.url,
    required this.title,
  });

  /// Directory entries store an empty title to mean "same as url" (seen on
  /// every non-HTML asset in test.zim -- application.css, assets/*, etc).
  String get displayTitle => title.isEmpty ? url : title;
}
