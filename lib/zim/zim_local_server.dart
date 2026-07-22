import 'dart:io';

import 'zim_archive.dart';

/// Loopback-only HTTP server that serves one .zim archive's entries by
/// path -- lets a real WebView (see lib/widgets/zim_webview.dart, used on
/// Android/Linux/Windows) render a .zim page with a real browser engine instead
/// of flutter_html's much weaker CSS/table support. Serving over real HTTP
/// (rather than a custom scheme or loadHtmlString) means the browser
/// resolves every relative `<a href>`/`<img src>`/`<link href>` itself,
/// using its own correct URL algorithm -- no hand-rolled percent-decoding
/// or relative-path-joining needed here at all, unlike the flutter_html
/// path (lib/providers/wiki_source.dart's resolvePath/_inlineStylesheets),
/// which remains as a fallback for platforms without a WebView plugin.
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

  /// Builds a URL without losing literal percent signs in ZIM entry names.
  /// Encoding each segment turns a stored `%2C` into `%252C` on the wire;
  /// Uri.pathSegments decodes it exactly once on the way back in.
  Uri urlForPath(String path) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    pathSegments: path.split('/'),
  );

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    _setSecurityHeaders(request.response);
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final path = request.uri.pathSegments.join('/');
    try {
      final resolvedPath = await archive.resolveEntryPath(path);
      if (resolvedPath == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (resolvedPath != path) {
        await request.response.redirect(
          urlForPath(resolvedPath),
          status: HttpStatus.temporaryRedirect,
        );
        return;
      }

      final content = await archive.getEntryContent(path);
      if (content == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = _contentTypeFor(content.mimetype);
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        content.mimetype.startsWith('text/html')
            ? 'no-cache'
            : 'public, max-age=31536000, immutable',
      );
      if (request.method != 'HEAD') request.response.add(content.bytes);
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$e');
      await request.response.close();
    }
  }

  void _setSecurityHeaders(HttpResponse response) {
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      // Archive HTML is untrusted. It may style itself and load its own
      // images/fonts/media, but it cannot execute code or reach the network.
      // JavaScript is also disabled at the WebView controller layer.
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline' data:; "
            "font-src 'self' data:; media-src 'self' data: blob:; script-src 'none'; "
            "connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'",
      );
  }

  ContentType _contentTypeFor(String mimetype) {
    final parts = mimetype.split(';');
    final primary = parts.first.trim();
    final slash = primary.indexOf('/');
    if (slash == -1) return ContentType.binary;
    try {
      final charsetPart = parts
          .skip(1)
          .cast<String?>()
          .firstWhere(
            (part) => part!.trim().toLowerCase().startsWith('charset='),
            orElse: () => null,
          );
      final charset = charsetPart?.split('=').skip(1).join('=').trim();
      return ContentType(
        primary.substring(0, slash),
        primary.substring(slash + 1),
        charset: charset == null || charset.isEmpty ? null : charset,
      );
    } catch (_) {
      return ContentType.binary;
    }
  }
}
