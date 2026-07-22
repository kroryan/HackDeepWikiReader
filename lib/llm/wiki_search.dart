import '../models/wiki_models.dart';
import '../providers/wiki_source.dart';

/// One search hit -- a page plus a bounded text snippet, cheap enough to
/// fold into a tool-result message without itself blowing the context
/// budget back open.
class WikiSearchHit {
  final String pageId;
  final String title;
  final String snippet;
  const WikiSearchHit({required this.pageId, required this.title, required this.snippet});
}

const _snippetMaxChars = 1000;

/// Backs the chat's `SEARCH_WIKI:` tool (see context_builder.dart's tool
/// instructions and chat_provider.dart's tool loop) -- mirrors the
/// backend's own agentic search tool (api/search_tool.py's build_zim_context/
/// search_zim, found via HackDeepWiki's own agent_loop.py), just without a
/// prebuilt full-text index: HackDeepWiki's backend leans on libzim's
/// bundled Xapian index, which this app has no equivalent of, so this
/// ranks by simple title/path substring match instead. Bounded to a
/// [limit] of hits with a capped snippet each, same idea as the backend
/// (never dump the whole wiki -- that's exactly what motivated adding a
/// search tool in the first place: this app's own "Pages in this wiki"
/// system-prompt list truncates for the same reason, see context_builder.dart).
Future<List<WikiSearchHit>> searchWiki(WikiSource source, String query, {int limit = 5}) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final scored = <MapEntry<WikiPage, int>>[];
  for (final p in source.structure.pages) {
    final title = p.title.toLowerCase();
    final id = p.id.toLowerCase();
    var score = 0;
    if (title == q) {
      score += 100;
    } else if (title.contains(q)) {
      score += 50;
    }
    if (id.contains(q)) score += 20;
    if (p.content.isNotEmpty && p.content.toLowerCase().contains(q)) score += 10;
    if (score > 0) scored.add(MapEntry(p, score));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));

  final hits = <WikiSearchHit>[];
  for (final entry in scored.take(limit)) {
    final page = entry.key;
    String text = page.content;
    if (text.isEmpty && source is ZimWikiSource) {
      text = await source.loadPlainText(page.id) ?? '';
    }
    hits.add(WikiSearchHit(
      pageId: page.id,
      title: page.title,
      snippet: text.length > _snippetMaxChars ? '${text.substring(0, _snippetMaxChars)}…' : text,
    ));
  }
  return hits;
}
