/// A locally-imported .hdwreader offline bundle (see
/// api/api.py::generate_hdwreader_export on the deepwiki-open backend).
/// Stored as a plain JSON map in Hive, same convention as Endpoint.
class BundleEntry {
  final String id;
  final String filePath;
  final String title;
  final int importedAt;

  const BundleEntry({
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

  factory BundleEntry.fromJson(Map<String, dynamic> json) => BundleEntry(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        title: json['title'] as String,
        importedAt: json['importedAt'] as int,
      );
}
