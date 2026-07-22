/// A locally-imported .zim archive -- fully offline, read directly off
/// disk (see lib/zim/zim_archive.dart), no HackDeepWiki server involved.
/// Stored as a plain JSON map in Hive, same convention as BundleEntry.
class ZimEntry {
  final String id;
  final String filePath;
  final String title;
  final int importedAt;

  const ZimEntry({
    required this.id,
    required this.filePath,
    required this.title,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'title': title,
        'importedAt': importedAt,
      };

  factory ZimEntry.fromJson(Map<String, dynamic> json) => ZimEntry(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        title: json['title'] as String,
        importedAt: json['importedAt'] as int,
      );
}
