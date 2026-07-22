import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny always-on file logger. The whole point of this file is to stop
/// guessing at the chat's "goes blank" bug: every unhandled exception (build
/// errors included) gets written here with its full stack trace and the
/// widget that threw it, plus explicit trace points around the chat open
/// path. One fresh log file per app launch (truncated at startup) so the
/// file always reflects the run you just did.
///
/// The log lives next to the Hive boxes in the app's documents directory.
/// The resolved path is printed to stdout on startup (so `flutter run` /
/// the bundled binary's stderr shows it) and written as the first line.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  String? _path;
  bool _ready = false;

  static String get _stamp {
    final t = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  /// Resolves the log file path (in the app documents dir), truncates it, and
  /// wires the global error handlers so nothing escapes unlogged.
  Future<void> init() async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (e, st) {
      // Fall back to CWD if path_provider blows up -- still log somewhere.
      dir = Directory.current;
      _raw('LOG INIT: path_provider failed ($e); falling back to ${dir.path}\n$st');
    }
    _path = '${dir.path}${Platform.pathSeparator}hackdeepwikireader.log';
    // Truncate so each launch starts clean.
    File(_path!).writeAsStringSync('=== HackDeepWikiReader log started $_stamp ===\n');
    _ready = true;
    _raw('LOG PATH: $_path\n');
    // Echo to stdout too, so the path is visible wherever the app was
    // launched from (terminal / the bundled binary's redirected output).
    // ignore: avoid_print
    print('[AppLogger] writing to $_path');

    // Sync widget-build / framework errors -- this is what catches the chat
    // panel's "No Overlay widget found"-style exceptions, with the full stack
    // and the widget context (which widget was building when it threw).
    FlutterError.onError = (FlutterErrorDetails details) {
      log('ERROR', 'FlutterError: ${details.exceptionAsString()}',
          error: details.exception, stack: details.stack, context: details.context?.toString());
    };
    // Async errors that escape Dart zones (futures, isolates, platform
    // channels) -- the ones FlutterError.onError doesn't see.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      log('ERROR', 'Unhandled async error: $error', error: error, stack: stack);
      return true; // swallow so it doesn't kill the app
    };
  }

  void _raw(String line) {
    final p = _path;
    if (p == null) return;
    try {
      File(p).writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // If the log itself can't be written, nowhere safe to complain.
    }
  }

  /// Append a timestamped entry. Synchronous write + flush so the entry is
  /// on disk before the app has any chance to hang/crash on the next frame.
  void log(String level, String message, {Object? error, StackTrace? stack, String? context}) {
    if (!_ready) return;
    final buffer = StringBuffer('[$_stamp] $level: $message\n');
    if (context != null && context.isNotEmpty) buffer.writeln('  context: $context');
    if (error != null) buffer.writeln('  error: $error');
    if (stack != null) buffer.writeln('  stack:\n$stack');
    _raw(buffer.toString());
  }

  void info(String message) => log('INFO', message);
  void warn(String message) => warnWith(message, null, null);
  void warnWith(String message, Object? error, StackTrace? stack) => log('WARN', message, error: error, stack: stack);
}