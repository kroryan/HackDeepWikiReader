import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bundle/hdwreader_bundle.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import 'bundle_viewer_screen.dart';
import 'endpoint_form_screen.dart';
import 'project_list_screen.dart';

/// The "library" -- home screen. Saved server endpoints + imported
/// .hdwreader bundles. This is the only screen with any create/delete
/// actions (managing the library itself); everything reachable from here is
/// read + chat only, per the app's read-only-client scope.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('HackDeepWikiReader')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: 'Servers',
            actionIcon: Icons.add,
            onAction: () => _addEndpoint(context),
          ),
          if (library.endpoints.isEmpty)
            const _EmptyHint(text: 'No servers yet. Add a HackDeepWiki backend URL to browse and chat with its wikis.'),
          for (final endpoint in library.endpoints)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.dns,
                  color: library.isReachable(endpoint.id) == true
                      ? Colors.green
                      : library.isReachable(endpoint.id) == false
                          ? Colors.red
                          : Colors.grey,
                ),
                title: Text(endpoint.name),
                subtitle: Text(endpoint.baseUrl),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProjectListScreen(endpoint: endpoint)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _addEndpoint(context, existing: endpoint);
                    } else if (value == 'delete') {
                      library.removeEndpoint(endpoint.id);
                    } else if (value == 'refresh') {
                      library.checkConnection(endpoint);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Test connection')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: 'Offline bundles',
            actionIcon: Icons.file_open,
            onAction: () => _importBundle(context),
          ),
          if (library.bundles.isEmpty)
            const _EmptyHint(text: 'No bundles yet. Import a .hdwreader file exported from HackDeepWiki to read it offline.'),
          for (final bundle in library.bundles)
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(bundle.title),
                subtitle: Text(bundle.filePath, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BundleViewerScreen(bundleEntry: bundle)),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => library.removeBundle(bundle.id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addEndpoint(BuildContext context, {dynamic existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EndpointFormScreen(existing: existing)),
    );
  }

  Future<void> _importBundle(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select a .hdwreader bundle',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    if (!context.mounted) return;
    try {
      final bundle = await HdwReaderBundle.open(path);
      if (!context.mounted) return;
      await context.read<LibraryProvider>().addBundle(path, bundle.title);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open bundle: $e')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData actionIcon;
  final VoidCallback onAction;

  const _SectionHeader({required this.title, required this.actionIcon, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        IconButton(icon: Icon(actionIcon), onPressed: onAction),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: Theme.of(context).appColors.muted)),
    );
  }
}
