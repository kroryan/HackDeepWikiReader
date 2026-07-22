import 'dart:convert';
import 'dart:typed_data';

import '../api/hackdeepwiki_client.dart';
import '../bundle/hdwreader_bundle.dart';
import '../models/endpoint.dart';
import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../models/wiki_models.dart';
import '../zim/zim_archive.dart';

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
  Future<VulnReport?> loadVulnReport({int? version}) async => bundle.vulnReport;

  @override
  Future<WebVulnReport?> loadWebVulnReport({int? version}) async => bundle.webVulnReport;

  @override
  Future<List<ReleaseInfo>> loadVulnReleases() async => const [];

  @override
  Future<List<ReleaseInfo>> loadWebVulnReleases() async => const [];
}

/// A locally-imported .zim archive (openzim.org/wiki/ZIM_file_format),
/// read directly off disk via lib/zim/zim_archive.dart -- no HackDeepWiki
/// server involved at all, the one place this app talks to anything
/// external is the user's own chosen LLM provider. .zim archives have no
/// security scan of their own (they're offline reference/doc dumps, not a
/// scanned repo or website) so the vuln/web-vuln hooks are all empty.
///
/// Unlike ServerWikiSource/BundleWikiSource, page content isn't loaded up
/// front -- .zim archives can be gigabytes, so `structure.pages[].content`
/// starts empty and [loadHtml] decompresses each entry lazily. The first
/// time a page is opened, the extracted plain-text is cached back onto its
/// WikiPage in `structure` (see [loadHtml]) so a later chat turn -- which
/// reads `structure.pageById(id)` synchronously (see ChatProvider.sendMessage)
/// -- still finds real content even though loading it here was async.
class ZimWikiSource implements WikiSource {
  final String zimId;
  final ZimArchive archive;
  @override
  final WikiStructure structure;

  ZimWikiSource._(this.zimId, this.archive, this.structure);

  static Future<ZimWikiSource> open(String zimId, String filePath) async {
    final archive = await ZimArchive.open(filePath);
    final entries = await archive.listEntries();
    // Matches libzim's own "article" filter (verified against test.zim: 36
    // text/html entries out of 56 total, the rest being metadata, redirects,
    // and the Xapian/listing index entries) -- these are the browsable pages.
    final pages = [
      for (final e in entries)
        if (!e.isRedirect && e.mimetype == 'text/html')
          WikiPage(id: e.path, title: e.title, content: '', filePaths: const [], importance: 'medium', relatedPages: const []),
    ];

    final mainPage = await archive.mainPagePath();
    if (mainPage != null) {
      final idx = pages.indexWhere((p) => p.id == mainPage);
      if (idx > 0) pages.insert(0, pages.removeAt(idx));
    }

    final title = await archive.getMetadataString('Title');
    final description = await archive.getMetadataString('Description');
    final fallbackTitle = filePath.split('/').last;

    final structure = WikiStructure(
      id: zimId,
      title: (title == null || title.isEmpty) ? fallbackTitle : title,
      description: description ?? '',
      pages: pages,
      sections: const [],
      rootSections: const [],
    );
    return ZimWikiSource._(zimId, archive, structure);
  }

  Future<void> close() => archive.close();

  @override
  String get sourceId => 'zim:$zimId';

  @override
  String get title => structure.title;

  @override
  String get description => structure.description;

  @override
  bool get isWebsite => false;

  @override
  Future<VulnReport?> loadVulnReport({int? version}) async => null;

  @override
  Future<WebVulnReport?> loadWebVulnReport({int? version}) async => null;

  @override
  Future<List<ReleaseInfo>> loadVulnReleases() async => const [];

  @override
  Future<List<ReleaseInfo>> loadWebVulnReleases() async => const [];

  /// Fetches the raw HTML for [path] (following one redirect hop if the
  /// path happens to be a redirect target), for the on-screen HTML view --
  /// with every `<link rel="stylesheet">` inlined as a `<style>` block (see
  /// [_inlineStylesheets]), since flutter_html only ever applies CSS it
  /// finds already inside the document. Also backfills the matching
  /// WikiPage's plain-text `content` the first time it's visited (see class
  /// doc).
  Future<String?> loadHtml(String path) async {
    final content = await archive.getEntryContent(path);
    if (content == null) return null;
    final rawHtml = utf8.decode(content.bytes, allowMalformed: true);
    final idx = structure.pages.indexWhere((p) => p.id == path);
    if (idx != -1 && structure.pages[idx].content.isEmpty) {
      structure.pages[idx] = structure.pages[idx].copyWithContent(_htmlToPlainText(rawHtml));
    }
    return _inlineStylesheets(rawHtml, path);
  }

  /// Plain-text extraction only -- no CSS inlining, no HTML returned. Used
  /// by search snippets and the chat tool loop (lib/llm/wiki_search.dart),
  /// where only the text matters and the CSS-fetching work loadHtml does
  /// would be wasted. Also backfills the page's cached content, same as
  /// [loadHtml] -- whichever one runs first for a given page wins.
  Future<String?> loadPlainText(String path) async {
    final content = await archive.getEntryContent(path);
    if (content == null) return null;
    final html = utf8.decode(content.bytes, allowMalformed: true);
    final text = _htmlToPlainText(html);
    final idx = structure.pages.indexWhere((p) => p.id == path);
    if (idx != -1 && structure.pages[idx].content.isEmpty) {
      structure.pages[idx] = structure.pages[idx].copyWithContent(text);
    }
    return text;
  }

  static final _stylesheetLinkRe =
      RegExp(r'<link\b[^>]*rel=["\047]stylesheet["\047][^>]*>', caseSensitive: false);
  static final _hrefAttrRe = RegExp(r'href=["\047]([^"\047]+)["\047]', caseSensitive: false);

  /// Replaces every `<link rel="stylesheet" href="...">` with an inline
  /// `<style>` block holding that stylesheet's real content, fetched
  /// straight from the archive -- real-world .zim HTML (verified against an
  /// actual Wikipedia dump) references a dozen+ external stylesheets
  /// (skin CSS, per-template "TemplateStyles" sheets, gadgets) that
  /// flutter_html has no way to fetch on its own, since it only parses
  /// `<style>` tags already present in the document (see
  /// html_parser.dart's styleTree(), which reads
  /// `getElementsByTagName("style")` and nothing network/asset-related).
  /// flutter_html's CSS support is still a subset of a real browser's, so
  /// this narrows the gap rather than closes it -- but it's the difference
  /// between "not loaded at all" and "loaded and applied wherever
  /// flutter_html's CSS engine can".
  Future<String> _inlineStylesheets(String html, String basePath) async {
    final matches = _stylesheetLinkRe.allMatches(html).toList();
    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final m in matches) {
      final hrefMatch = _hrefAttrRe.firstMatch(m.group(0)!);
      buffer.write(html.substring(lastEnd, m.start));
      lastEnd = m.end;
      if (hrefMatch == null) continue;
      final cssPath = resolvePath(basePath, hrefMatch.group(1)!);
      final css = await loadAsset(cssPath);
      if (css == null) continue;
      buffer
        ..write('<style>')
        ..write(utf8.decode(css, allowMalformed: true))
        ..write('</style>');
    }
    buffer.write(html.substring(lastEnd));
    return _stripBackgroundDeclarations(buffer.toString());
  }

  static final _styleBlockRe = RegExp(r'(<style\b[^>]*>)([\s\S]*?)(</style>)', caseSensitive: false);
  static final _backgroundDeclRe = RegExp(r'background(-color)?\s*:\s*[^;{}]+;?', caseSensitive: false);

  /// Real .zim pages routinely set a full-bleed dark `background` on
  /// generic layout wrapper elements (verified: a Wikipedia mobile
  /// main-page layout paints `#container`/`#content` solid black,
  /// expecting a real browser's viewport-filling body underneath) --
  /// applied inside flutter_html's much simpler box model, that reliably
  /// painted over the reader's own theme with nothing else compensating,
  /// making entire pages look blank. Reader mode doesn't need page-authored
  /// backgrounds at all (only text/border/link colors matter for
  /// readability), so this strips every `background`/`background-color`
  /// declaration from every `<style>` block -- covers both stylesheets just
  /// inlined by [_inlineStylesheets] above and any the page's own HTML
  /// already had inline (e.g. Wikipedia's per-template "TemplateStyles"
  /// blocks).
  String _stripBackgroundDeclarations(String html) {
    return html.replaceAllMapped(_styleBlockRe, (m) {
      final cleaned = m.group(2)!.replaceAll(_backgroundDeclRe, '');
      return '${m.group(1)}$cleaned${m.group(3)}';
    });
  }

  /// Fetches a non-HTML asset (image, CSS, ...) referenced from within a
  /// page's HTML, by its resolved in-archive path.
  Future<Uint8List?> loadAsset(String path) async {
    final content = await archive.getEntryContent(path);
    return content?.bytes;
  }

  /// Resolves a relative href/src found inside the entry at [basePath]
  /// against that entry's own directory -- .zim internal links are always
  /// relative, exactly like a normal filesystem/URL path. Real archive HTML
  /// percent-encodes path segments (verified against an actual Wikipedia
  /// .zim) -- decoded exactly once, matching normal browser URL semantics.
  /// Some filenames look "double-encoded" at a glance (`%252C` in the HTML)
  /// but the archive's actual stored path is the *singly*-decoded form
  /// (`%2C`, still containing a literal percent sign) -- confirmed by
  /// direct lookup, not decoded further.
  static String resolvePath(String basePath, String relative) {
    var rel = relative.split('#').first.split('?').first;
    try {
      rel = Uri.decodeComponent(rel);
    } catch (_) {
      // Not (validly) percent-encoded -- use as-is.
    }
    if (rel.startsWith('/')) return rel.substring(1);
    final baseDir = basePath.contains('/') ? basePath.substring(0, basePath.lastIndexOf('/')) : '';
    final combined = baseDir.isEmpty ? rel : '$baseDir/$rel';
    final out = <String>[];
    for (final part in combined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(part);
      }
    }
    return out.join('/');
  }
}

/// Mirrors the backend's own zim_reader.py plain-text extraction (same two
/// regexes) so chat context built from a .zim page reads like text, not a
/// wall of markup.
String _htmlToPlainText(String html) {
  var text = html.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
  text = text.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}
