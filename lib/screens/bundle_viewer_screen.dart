import 'package:flutter/material.dart';

import '../bundle/hdwreader_bundle.dart';
import '../models/bundle_entry.dart';
import '../providers/wiki_source.dart';
import 'wiki_viewer_screen.dart';

/// Opens a locally-imported .hdwreader bundle and hands it to
/// WikiViewerScreen through the same WikiSource interface a live server
/// connection uses -- the viewer itself has no idea which one it's looking at.
class BundleViewerScreen extends StatelessWidget {
  final BundleEntry bundleEntry;
  const BundleViewerScreen({super.key, required this.bundleEntry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HdwReaderBundle>(
      future: HdwReaderBundle.open(bundleEntry.filePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(bundleEntry.title)),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not open this bundle:\n${snapshot.error}'),
            ),
          );
        }
        final source = BundleWikiSource(bundleId: bundleEntry.id, bundle: snapshot.data!);
        return WikiViewerScreen(source: source);
      },
    );
  }
}
