import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../bundle/hdwreader_bundle.dart';
import '../providers/library_provider.dart';
import '../storage/app_directories.dart';
import '../theme/app_theme.dart';
import '../zim/zim_archive.dart';
import 'bundle_viewer_screen.dart';
import 'endpoint_form_screen.dart';
import 'project_list_screen.dart';
import 'settings_screen.dart';
import 'zim_viewer_screen.dart';

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
      appBar: AppBar(
        title: const Text('HackDeepWikiReader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
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
          const SizedBox(height: 24),
          _SectionHeader(
            title: '.zim archives',
            actionIcon: Icons.file_open,
            onAction: () => _importZim(context),
          ),
          if (library.zims.isEmpty)
            const _EmptyHint(
              text: 'No .zim archives yet. Import a .zim file (e.g. from Kiwix) to browse and chat with it '
                  'fully offline -- no server needed to read it.',
            ),
          for (final zim in library.zims)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(zim.title),
                subtitle: Text(zim.filePath, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ZimViewerScreen(zimEntry: zim)),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => library.removeZim(zim.id),
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

  Future<void> _importZim(BuildContext context) async {
    // FileType.custom + allowedExtensions doesn't work for .zim on Android
    // -- confirmed live on a real device: file_picker's Android plugin
    // resolves each allowed extension to a MIME type via Android's own
    // MimeTypeMap before it'll even open the picker
    // (FilePickerPlugin.java's "custom" case), and "zim" has no registered
    // MIME type on Android, so that lookup comes back empty and the picker
    // refuses to open at all -- silently from the user's POV (the button
    // just does nothing), loudly in the log (a PlatformException). Same
    // fix _importBundle above already uses for the equally-unregistered
    // .hdwreader extension: FileType.any, then filter by extension here in
    // Dart instead of relying on Android's MIME registry.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select a .zim archive',
    );
    if (result == null || result.files.single.path == null) return;
    final pickedPath = result.files.single.path!;
    if (!pickedPath.toLowerCase().endsWith('.zim')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please pick a .zim file.')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    try {
      // Copied into the app's own storage (not just referenced in place) --
      // file_picker's returned path isn't guaranteed to stay valid long-term
      // on every platform (e.g. Android content-picker cache locations), and
      // this matches how imported .hdwreader bundles are already handled.
      final zimsDir = AppDirectories.zims;
      if (!await zimsDir.exists()) await zimsDir.create(recursive: true);
      final id = const Uuid().v4();
      final destPath = '${zimsDir.path}/$id.zim';
      await File(pickedPath).copy(destPath);

      final fileName = pickedPath.split(Platform.pathSeparator).last;
      final archive = await ZimArchive.open(destPath);
      final metaTitle = await archive.getMetadataString('Title');
      await archive.close();

      if (!context.mounted) return;
      await context.read<LibraryProvider>().addZim(destPath, (metaTitle == null || metaTitle.isEmpty) ? fileName : metaTitle);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import .zim archive: $e')),
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
