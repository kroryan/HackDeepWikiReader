import 'package:flutter/material.dart';

import '../models/wiki_models.dart';

/// Section/page tree navigator -- mirrors WikiTreeView.tsx on the web app.
/// Falls back to a flat page list when the wiki has no section hierarchy
/// (e.g. a legacy cache/bundle without sections).
class WikiTreeView extends StatelessWidget {
  final WikiStructure structure;
  final String? selectedPageId;
  final ValueChanged<String> onSelectPage;

  const WikiTreeView({
    super.key,
    required this.structure,
    required this.selectedPageId,
    required this.onSelectPage,
  });

  @override
  Widget build(BuildContext context) {
    if (structure.sections.isEmpty || structure.rootSections.isEmpty) {
      return ListView(
        children: [for (final page in structure.pages) _pageTile(context, page)],
      );
    }
    final sectionsById = {for (final s in structure.sections) s.id: s};
    return ListView(
      children: [for (final id in structure.rootSections) _sectionTile(context, sectionsById, id, 0)],
    );
  }

  Widget _sectionTile(BuildContext context, Map<String, WikiSection> byId, String sectionId, int depth) {
    final section = byId[sectionId];
    if (section == null) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: depth == 0,
        title: Padding(
          padding: EdgeInsets.only(left: depth * 8.0),
          child: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        children: [
          for (final pageId in section.pages)
            if (structure.pageById(pageId) != null) _pageTile(context, structure.pageById(pageId)!, depth: depth + 1),
          for (final subId in section.subsections) _sectionTile(context, byId, subId, depth + 1),
        ],
      ),
    );
  }

  Widget _pageTile(BuildContext context, WikiPage page, {int depth = 0}) {
    final selected = page.id == selectedPageId;
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: ListTile(
        dense: true,
        selected: selected,
        title: Text(page.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => onSelectPage(page.id),
      ),
    );
  }
}
