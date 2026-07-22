import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/endpoint.dart';
import '../models/provider_config.dart';
import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';

/// Thin REST client for one connected HackDeepWiki backend endpoint. Every
/// method maps 1:1 to a route already exposed by api/api.py -- this app
/// never adds or changes backend endpoints, it only ever reads from them
/// (no generation, no scan-triggering: see the endpoints deliberately NOT
/// present here, like POST /api/wiki_cache or /ws/vuln_scan).
///
/// To add a new read-only feature later: add one method here that mirrors
/// the existing pattern (build the URL, GET, decode, map to a model), then
/// consume it from a provider. No other file needs to change.
class HackDeepWikiClient {
  final Endpoint endpoint;
  final http.Client _http;

  HackDeepWikiClient(this.endpoint, {http.Client? client}) : _http = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${endpoint.normalizedBaseUrl}$path').replace(queryParameters: query);

  Future<bool> testConnection() async {
    try {
      final res = await _http.get(_uri('/health')).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<ProcessedProject>> listProcessedProjects() async {
    final res = await _http.get(_uri('/api/processed_projects'));
    _throwIfError(res);
    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['projects'] as List? ?? []);
    return list.map((e) => ProcessedProject.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>?> getWikiCache({
    required String owner,
    required String repo,
    required String repoType,
    required String language,
    bool? comprehensive,
    int? pageCount,
    int? version,
  }) async {
    final res = await _http.get(_uri('/api/wiki_cache', {
      'owner': owner,
      'repo': repo,
      'repo_type': repoType,
      'language': language,
      if (comprehensive != null) 'comprehensive': comprehensive.toString(),
      if (pageCount != null) 'page_count': pageCount.toString(),
      if (version != null) 'version': version.toString(),
    }));
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    final data = jsonDecode(res.body);
    return data == null ? null : data as Map<String, dynamic>;
  }

  Future<List<ReleaseInfo>> getWikiReleases({
    required String owner,
    required String repo,
    required String repoType,
    required String language,
  }) async {
    final res = await _http.get(_uri('/api/wiki_cache/releases', {
      'owner': owner,
      'repo': repo,
      'repo_type': repoType,
      'language': language,
    }));
    _throwIfError(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['releases'] as List? ?? []).map((e) => ReleaseInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<VulnReport?> getVulnReport({
    required String owner,
    required String repo,
    required String repoType,
    required String language,
    int? version,
  }) async {
    final res = await _http.get(_uri('/api/vuln_cache', {
      'owner': owner,
      'repo': repo,
      'repo_type': repoType,
      'language': language,
      if (version != null) 'version': version.toString(),
    }));
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return VulnReport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ReleaseInfo>> getVulnReleases({
    required String owner,
    required String repo,
    required String repoType,
    required String language,
  }) async {
    final res = await _http.get(_uri('/api/vuln_cache/releases', {
      'owner': owner,
      'repo': repo,
      'repo_type': repoType,
      'language': language,
    }));
    _throwIfError(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['releases'] as List? ?? []).map((e) => ReleaseInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<WebVulnReport?> getWebVulnReport({
    required String owner,
    required String repo,
    required String language,
    int? version,
  }) async {
    final res = await _http.get(_uri('/api/web_vuln_cache', {
      'owner': owner,
      'repo': repo,
      'language': language,
      if (version != null) 'version': version.toString(),
    }));
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return WebVulnReport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ReleaseInfo>> getWebVulnReleases({
    required String owner,
    required String repo,
    required String language,
  }) async {
    final res = await _http.get(_uri('/api/web_vuln_cache/releases', {
      'owner': owner,
      'repo': repo,
      'language': language,
    }));
    _throwIfError(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['releases'] as List? ?? []).map((e) => ReleaseInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Provider/model config -- same source UserSelector.tsx reads on the web
  /// app. Shape: {"providers": [{"id","name","models":[{"id","name"}],
  /// "supportsCustomModel"}], "defaultProvider": "..."}
  Future<ModelsConfig> getModelsConfig() async {
    final res = await _http.get(_uri('/models/config'));
    _throwIfError(res);
    return ModelsConfig.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- .zim archives on this server (api/zim_reader.py / /api/zim/*) ---

  Future<List<Map<String, dynamic>>> listZimArchives() async {
    final res = await _http.get(_uri('/api/zim/drop_dir'));
    _throwIfError(res);
    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['archives'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getZimIndex(String zimId) async {
    final res = await _http.get(_uri('/api/zim/$zimId/index'));
    _throwIfError(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Returns raw HTML (see api/api.py::get_zim_entry -- response_class is
  /// HTMLResponse, with a `<base>` tag injected so relative asset/link
  /// paths resolve against /api/zim/{zimId}/raw/...). Render with
  /// flutter_html, not as Markdown.
  Future<String> getZimEntryHtml(String zimId, String path) async {
    final res = await _http.get(_uri('/api/zim/$zimId/entry', {'path': path}));
    _throwIfError(res);
    return res.body;
  }

  /// Absolute URL for a raw asset/sub-resource inside the archive (images,
  /// CSS, etc.) -- used as the base URL for flutter_html's image/link
  /// resolution when rendering getZimEntryHtml's output.
  String zimRawBaseUrl(String zimId) => '${endpoint.normalizedBaseUrl}/api/zim/$zimId/raw/';

  Future<List<Map<String, dynamic>>> searchZim(String zimId, String query) async {
    final res = await _http.get(_uri('/api/zim/$zimId/search', {'q': query}));
    _throwIfError(res);
    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['results'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HackDeepWikiApiException(res.statusCode, res.body);
    }
  }

  void close() => _http.close();
}

class HackDeepWikiApiException implements Exception {
  final int statusCode;
  final String body;
  HackDeepWikiApiException(this.statusCode, this.body);
  @override
  String toString() => 'HackDeepWiki API error $statusCode: $body';
}
