import 'dart:io';

import 'zim_archive.dart';

/// Loopback-only HTTP server that serves one .zim archive's entries by
/// path -- lets a real WebView (see lib/widgets/zim_webview.dart, used on
/// Android/Windows) render a .zim page with a real browser engine instead
/// of flutter_html's much weaker CSS/table support. Serving over real HTTP
/// (rather than a custom scheme or loadHtmlString) means the browser
/// resolves every relative `<a href>`/`<img src>`/`<link href>` itself,
/// using its own correct URL algorithm -- no hand-rolled percent-decoding
/// or relative-path-joining needed here at all, unlike the flutter_html
/// path (lib/providers/wiki_source.dart's resolvePath/_inlineStylesheets),
/// which still carries that logic for Linux, where no WebView plugin
/// exists.
///
/// Bound to 127.0.0.1 only (not 0.0.0.0) -- never reachable from the
/// network, matching this app's "everything except the LLM call is fully
/// offline" scope.
class ZimLocalServer {
  final ZimArchive archive;
  HttpServer? _server;

  ZimLocalServer(this.archive);

  int get port => _server?.port ?? 0;
  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    // Uri.path is already percent-decoded, exactly matching what a real
    // link's resolved target path is meant to be.
    var path = request.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    try {
      final content = await archive.getEntryContent(path);
      if (content == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = _contentTypeFor(content.mimetype);
      request.response.add(content.bytes);
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$e');
      await request.response.close();
    }
  }

  ContentType _contentTypeFor(String mimetype) {
    final parts = mimetype.split(';');
    final primary = parts.first.trim();
    final slash = primary.indexOf('/');
    if (slash == -1) return ContentType.binary;
    try {
      return ContentType(primary.substring(0, slash), primary.substring(slash + 1));
    } catch (_) {
      return ContentType.binary;
    }
  }
}
