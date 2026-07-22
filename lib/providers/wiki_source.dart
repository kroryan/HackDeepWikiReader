import '../api/hackdeepwiki_client.dart';
import '../bundle/hdwreader_bundle.dart';
import '../models/endpoint.dart';
import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';

/// Unifies "a wiki browsed on a connected server" and "a wiki opened from a
/// local .hdwreader bundle" behind one interface, so every screen below the
/// library (wiki viewer, security screen, chat) is written once and works
/// against either source. To add a third source type later (e.g. a cached
/// offline copy of a server wiki), implement this interface -- no existing
/// screen needs to change.
abstract class WikiSource {
  /// Stable key for chat-history storage (LocalStorage.*ChatSessions) and
  /// provider caching -- must be unique per distinct wiki.
  String get sourceId;
  String get title;
  String get description;
  WikiStructure get structure;
  bool get isWebsite;

  /// True only for a live server connection -- chat needs a real LLM
  /// backend, so a standalone bundle (no endpoint) can't offer it.
  bool get canChat;

  Future<VulnReport?> loadVulnReport({int? version});
  Future<WebVulnReport?> loadWebVulnReport({int? version});
  Future<List<ReleaseInfo>> loadVulnReleases();
  Future<List<ReleaseInfo>> loadWebVulnReleases();
}

class ServerWikiSource implements WikiSource {
  final Endpoint endpoint;
  final ProcessedProject project;
  final HackDeepWikiClient client;
  @override
  final WikiStructure structure;
  final Map<String, dynamic> wikiCacheData;

  ServerWikiSource({
    required this.endpoint,
    required this.project,
    required this.client,
    required this.structure,
    required this.wikiCacheData,
  });

  @override
  String get sourceId => 'server:${endpoint.id}:${project.repoType}:${project.owner}:${project.repo}:${project.language}';

  @override
  String get title => structure.title;

  @override
  String get description => structure.description;

  @override
  bool get isWebsite => project.isWebsite;

  @override
  bool get canChat => true;

  @override
  Future<VulnReport?> loadVulnReport({int? version}) => client.getVulnReport(
        owner: project.owner,
        repo: project.repo,
        repoType: project.repoType,
        language: project.language,
        version: version,
      );

  @override
  Future<WebVulnReport?> loadWebVulnReport({int? version}) => client.getWebVulnReport(
        owner: project.owner,
        repo: project.repo,
        language: project.language,
        version: version,
      );

  @override
  Future<List<ReleaseInfo>> loadVulnReleases() => client.getVulnReleases(
        owner: project.owner,
        repo: project.repo,
        repoType: project.repoType,
        language: project.language,
      );

  @override
  Future<List<ReleaseInfo>> loadWebVulnReleases() => client.getWebVulnReleases(
        owner: project.owner,
        repo: project.repo,
        language: project.language,
      );
}

class BundleWikiSource implements WikiSource {
  final String bundleId;
  final HdwReaderBundle bundle;

  BundleWikiSource({required this.bundleId, required this.bundle});

  @override
  String get sourceId => 'bundle:$bundleId';

  @override
  String get title => bundle.title;

  @override
  String get description => bundle.structure.description;

  @override
  WikiStructure get structure => bundle.structure;

  @override
  bool get isWebsite => bundle.repoType == 'website';

  @override
  bool get canChat => false; // no live backend bundled with an offline file

  @override
  Future<VulnReport?> loadVulnReport({int? version}) async => bundle.vulnReport;

  @override
  Future<WebVulnReport?> loadWebVulnReport({int? version}) async => bundle.webVulnReport;

  @override
  Future<List<ReleaseInfo>> loadVulnReleases() async => const [];

  @override
  Future<List<ReleaseInfo>> loadWebVulnReleases() async => const [];
}
