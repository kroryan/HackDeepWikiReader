import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_overlay_controller.dart';
import '../providers/wiki_source.dart';
import '../widgets/wiki_markdown_view.dart';
import '../widgets/wiki_tree_view.dart';
import 'security_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final pages = widget.source.structure.pages;
    _currentPageId = pages.isNotEmpty ? pages.first.id : null;
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
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Chat',
            onPressed: () => context
                .read<ChatOverlayController>()
                .openFor(widget.source, currentPageId: _currentPageId),
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
              Expanded(
                child: WikiTreeView(
                  structure: structure,
                  selectedPageId: _currentPageId,
                  onSelectPage: (id) {
                    setState(() => _currentPageId = id);
                    context.read<ChatOverlayController>().updateCurrentPage(widget.source.sourceId, id);
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: WikiMarkdownView(data: page.content),
            ),
    );
  }
}
