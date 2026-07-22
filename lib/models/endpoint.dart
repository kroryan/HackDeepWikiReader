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

  /// Builds baseUrl from separate address/port fields -- see
  /// EndpointFormScreen, which collects these as two fields (not one URL
  /// text box) specifically so "which port do I use" has an unambiguous
  /// answer instead of the user guessing between the browser port (3000)
  /// and the API port (8001, what this app actually needs).
  static String buildBaseUrl({required String scheme, required String host, required int port}) =>
      '$scheme://$host:$port';

  Uri get _uri => Uri.tryParse(normalizedBaseUrl) ?? Uri.parse('http://127.0.0.1:8001');
  String get scheme => _uri.hasScheme ? _uri.scheme : 'http';
  String get host => _uri.host.isNotEmpty ? _uri.host : '127.0.0.1';
  int get port => _uri.hasPort ? _uri.port : 8001;
}
