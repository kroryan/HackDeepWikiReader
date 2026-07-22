/// A saved HackDeepWiki backend connection -- "your library of endpoints".
/// Stored as a plain JSON map in Hive (no generated TypeAdapter needed, so
/// adding a field here never requires a codegen step -- see
/// lib/storage/local_storage.dart).
class Endpoint {
  final String id;
  final String name;
  final String baseUrl; // e.g. http://192.168.1.50:8001
  final String? lastUsedProvider;
  final String? lastUsedModel;

  const Endpoint({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lastUsedProvider,
    this.lastUsedModel,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lastUsedProvider': lastUsedProvider,
        'lastUsedModel': lastUsedModel,
      };

  factory Endpoint.fromJson(Map<String, dynamic> json) => Endpoint(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        lastUsedProvider: json['lastUsedProvider'] as String?,
        lastUsedModel: json['lastUsedModel'] as String?,
      );

  Endpoint copyWith({String? name, String? baseUrl, String? lastUsedProvider, String? lastUsedModel}) => Endpoint(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        lastUsedProvider: lastUsedProvider ?? this.lastUsedProvider,
        lastUsedModel: lastUsedModel ?? this.lastUsedModel,
      );

  /// baseUrl with any trailing slash stripped, so callers can always do
  /// '${endpoint.normalizedBaseUrl}/api/...' without worrying about '//'.
  String get normalizedBaseUrl => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}
