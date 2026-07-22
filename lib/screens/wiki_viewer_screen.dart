import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wiki_models.dart';
import '../providers/chat_overlay_controller.dart';
import '../providers/wiki_source.dart';
import '../widgets/wiki_markdown_view.dart';
import '../widgets/wiki_tree_view.dart';
import '../widgets/zim_html_view.dart';
import '../widgets/zim_webview.dart';
import 'security_screen.dart';

/// Real WebView plugins only cover Android/Windows (see zim_webview.dart's
/// doc comment) -- Linux keeps the flutter_html-based reader-mode fallback.
bool get _hasZimWebView =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows;

/// Read-only wiki viewer: section tree sidebar + Markdown page content.
/// Works identically whether [source] is a live server wiki or a local
/// .hdwreader bundle -- everything it needs comes from the WikiSource
/// interface. No edit/generate/scan actions exist here by design.
class WikiViewerScreen extends StatefulWidget {
  final WikiSource source;
  const WikiViewerScreen({super.key, required this.source});

  @override
  State<WikiViewerScreen> createState() => _WikiViewerScreenState();
}

class _WikiViewerScreenState extends State<WikiViewerScreen> {
  String? _currentPageId;
  String _treeFilter = '';

  @override
  void initState() {
    super.initState();
    final pages = widget.source.structure.pages;
    _currentPageId = pages.isNotEmpty ? pages.first.id : null;
  }

  @override
  void dispose() {
    final source = widget.source;
    if (source is ZimWikiSource) source.close();
    super.dispose();
  }

  void _navigateTo(String pageId) {
    setState(() => _currentPageId = pageId);
    context.read<ChatOverlayController>().updateCurrentPage(widget.source.sourceId, pageId);
  }

  @override
  Widget build(BuildContext context) {
    final structure = widget.source.structure;
    final page = _currentPageId != null ? structure.pageById(_currentPageId!) : null;

    return Scaffold(
      appBar: AppBar(
        // Scaffold only auto-shows ONE leading icon, and having a `drawer`
        // set below makes it default to the hamburger/menu icon instead of
        // the back button -- silently swallowing the only way out of this
        // screen (had to force-close and reopen the whole app to leave a
        // wiki). Restore the back button explicitly and move the drawer
        // toggle to `actions` instead.
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop())
            : null,
        title: Text(widget.source.title, overflow: TextOverflow.ellipsis),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Pages',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: widget.source.isWebsite ? 'Website Security' : 'Security Analysis',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SecurityScreen(source: widget.source)),
            ),
          ),
          IconButton(
            icon: Icon(context.watch<ChatOverlayController>().isOpen
                ? Icons.chat_bubble
                : Icons.chat_bubble_outline),
            tooltip: context.watch<ChatOverlayController>().isOpen ? 'Hide chat' : 'Chat',
            onPressed: () => context
                .read<ChatOverlayController>()
                .toggle(widget.source, currentPageId: _currentPageId),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(structure.title, style: Theme.of(context).textTheme.titleMedium),
              ),
              // .zim archives are shown as a flat, searchable index (like
              // the web app's own .zim reader sidebar) instead of a section
              // tree -- most archives have no natural section hierarchy, and
              // some hold thousands of entries where search matters more
              // than browsing.
              if (widget.source is ZimWikiSource)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search this archive…',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _treeFilter = v.trim().toLowerCase()),
                  ),
                ),
              Expanded(
                child: WikiTreeView(
                  structure: _filteredStructure(structure),
                  selectedPageId: _currentPageId,
                  onSelectPage: (id) {
                    _navigateTo(id);
                    Navigator.of(context).pop(); // close drawer
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: page == null
          ? const Center(child: Text('No pages in this wiki.'))
          : widget.source is ZimWikiSource
              ? (_hasZimWebView
                  ? ZimWebViewPage(source: widget.source as ZimWikiSource, path: page.id, onNavigate: _navigateTo)
                  : _ZimPageBody(source: widget.source as ZimWikiSource, path: page.id, onNavigate: _navigateTo))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: WikiMarkdownView(data: page.content),
                ),
    );
  }

  WikiStructure _filteredStructure(WikiStructure structure) {
    if (_treeFilter.isEmpty || structure.sections.isNotEmpty) return structure;
    final filtered = structure.pages
        .where((p) => p.title.toLowerCase().contains(_treeFilter) || p.id.toLowerCase().contains(_treeFilter))
        .toList();
    return WikiStructure(
      id: structure.id,
      title: structure.title,
      description: structure.description,
      pages: filtered,
      sections: structure.sections,
      rootSections: structure.rootSections,
    );
  }
}

/// Decompresses and renders one .zim entry -- a FutureBuilder keyed by
/// [path] so navigating to a new page (drawer, or a link tapped inside the
/// HTML itself) re-triggers loading instead of showing stale content.
class _ZimPageBody extends StatelessWidget {
  final ZimWikiSource source;
  final String path;
  final ValueChanged<String> onNavigate;

  const _ZimPageBody({required this.source, required this.path, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      key: ValueKey(path),
      future: source.loadHtml(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load this page: ${snapshot.error ?? 'not found in archive'}'),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ZimHtmlView(source: source, path: path, html: snapshot.data!, onNavigate: onNavigate),
        );
      },
    );
  }
}
