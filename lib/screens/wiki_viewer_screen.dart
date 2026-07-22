import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../providers/wiki_source.dart';
import '../widgets/wiki_tree_view.dart';
import 'chat_screen.dart';
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
        title: Text(widget.source.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.security),
            tooltip: widget.source.isWebsite ? 'Website Security' : 'Security Analysis',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SecurityScreen(source: widget.source)),
            ),
          ),
          if (widget.source.canChat)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(source: widget.source, currentPageId: _currentPageId),
                ),
              ),
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
              child: MarkdownBody(
                data: page.content,
                selectable: true,
                onTapLink: (text, href, title) {
                  // External links only (no local repo file browsing in this app).
                },
              ),
            ),
    );
  }
}
