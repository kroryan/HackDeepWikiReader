import 'package:flutter/material.dart';

import '../models/zim_entry.dart';
import '../providers/wiki_source.dart';
import 'wiki_viewer_screen.dart';

/// Opens a locally-imported .zim archive and hands it to WikiViewerScreen
/// through the same WikiSource interface a live server connection or a
/// .hdwreader bundle uses -- the viewer doesn't know (or care) that this one
/// reads its pages by decompressing them off disk instead of already having
/// them in memory.
class ZimViewerScreen extends StatelessWidget {
  final ZimEntry zimEntry;
  const ZimViewerScreen({super.key, required this.zimEntry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ZimWikiSource>(
      future: ZimWikiSource.open(zimEntry.id, zimEntry.filePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(zimEntry.title)),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not open this .zim archive:\n${snapshot.error}'),
            ),
          );
        }
        return WikiViewerScreen(source: snapshot.data!);
      },
    );
  }
}
