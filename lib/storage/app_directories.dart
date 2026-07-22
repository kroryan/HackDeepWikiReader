import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Owns every private file created by the reader.
///
/// On Linux the root is below XDG_DATA_HOME (normally
/// `~/.local/share/com.kroryan.hackdeepwikireader`), never Documents.
class AppDirectories {
  AppDirectories._();

  static late final Directory root;
  static late final Directory data;
  static late final Directory zims;
  static late final Directory logs;
  static Directory? legacyDocuments;

  static String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  static Future<void> init() async {
    root = await getApplicationSupportDirectory();
    data = Directory(_join(root.path, 'data'));
    zims = Directory(_join(root.path, 'zims'));
    logs = Directory(_join(root.path, 'logs'));
    await Future.wait([
      root.create(recursive: true),
      data.create(recursive: true),
      zims.create(recursive: true),
      logs.create(recursive: true),
    ]);

    // Releases up to 1.0.0 incorrectly used the public Documents directory
    // for private state. Migrate only the exact files owned by this app.
    try {
      legacyDocuments = await getApplicationDocumentsDirectory();
      if (legacyDocuments!.absolute.path != root.absolute.path) {
        await _migrateLegacyFiles();
      }
    } catch (_) {
      // An unavailable public Documents directory must not block startup.
    }
  }

  static Future<void> _migrateLegacyFiles() async {
    final legacy = legacyDocuments!;
    const hiveBoxes = [
      'endpoints',
      'bundles',
      'zims',
      'chat_sessions',
      'llm_connections',
      'settings',
    ];
    for (final box in hiveBoxes) {
      final source = File(_join(legacy.path, '$box.hive'));
      final destination = File(_join(data.path, '$box.hive'));
      if (await source.exists() && !await destination.exists()) {
        await _moveFile(source, destination);
        final staleLock = File(_join(legacy.path, '$box.lock'));
        if (await staleLock.exists()) await staleLock.delete();
      }
    }

    final oldZims = Directory(_join(legacy.path, 'zims'));
    if (await oldZims.exists()) {
      await for (final entity in oldZims.list(followLinks: false)) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.zim')) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        final destination = File(_join(zims.path, name));
        if (!await destination.exists()) await _moveFile(entity, destination);
      }
      if (await oldZims.list(followLinks: false).isEmpty) {
        await oldZims.delete();
      }
    }

    final oldLog = File(_join(legacy.path, 'hackdeepwikireader.log'));
    final previousLog = File(_join(logs.path, 'previous.log'));
    if (await oldLog.exists()) {
      if (await previousLog.exists()) await previousLog.delete();
      await _moveFile(oldLog, previousLog);
    }
  }

  static Future<void> _moveFile(File source, File destination) async {
    await destination.parent.create(recursive: true);
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      await source.copy(destination.path);
      if (await destination.length() == await source.length()) {
        await source.delete();
      }
    }
  }

  /// Maps a ZIM path saved by an affected release to its migrated path.
  static String migratedZimPath(String oldPath) {
    final legacy = legacyDocuments;
    if (legacy == null) return oldPath;
    final oldPrefix = '${_join(legacy.path, 'zims')}${Platform.pathSeparator}';
    if (!oldPath.startsWith(oldPrefix)) return oldPath;
    final name = oldPath.substring(oldPrefix.length);
    return _join(zims.path, name);
  }
}
