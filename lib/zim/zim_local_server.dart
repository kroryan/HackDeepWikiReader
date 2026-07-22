import 'dart:convert';
import 'dart:io';

import '../utils/app_logger.dart';
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
  // Whether served pages may run their own JavaScript -- see
  // zim_webview.dart's doc for why this is Android-only. When true,
  // connect-src also relaxes to 'self' (same-origin fetch/XHR only, e.g. a
  // script loading its own archive-provided JSON/data file) -- confirmed
  // live this is actually needed, not just script-src: a real archive's
  // own script hung on "Loading..." forever fetching its own data file
  // until this was allowed. 'self' here still only ever means "this same
  // loopback-only local server," so it changes nothing about this server
  // never being reachable from, or reaching out to, the real network.
  // frame-src and every other directive stay 'none' regardless.
  final bool allowScripts;
  HttpServer? _server;

  ZimLocalServer(this.archive, {this.allowScripts = false});

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
    final stopwatch = Stopwatch()..start();
    final requestPath = request.uri.pathSegments.join('/');
    _setSecurityHeaders(request.response);
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    final path = requestPath;
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
      if (request.method != 'HEAD') {
        request.response.add(
          content.mimetype.startsWith('text/html')
              ? _withViewportMeta(content.bytes)
              : content.bytes,
        );
      }
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('$e');
      await request.response.close();
    } finally {
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds >= 500) {
        AppLogger.instance.warn(
          'Slow ZIM asset: ${stopwatch.elapsedMilliseconds}ms $requestPath',
        );
      }
    }
  }

  /// Injects a standard viewport meta tag (width=device-width,
  /// initial-scale=1) right after the opening head tag when a page doesn't
  /// already have one -- confirmed live on a real Android device: a real .zim
  /// archive (a DevDocs-format export, Python's docs) had no viewport meta
  /// tag at all (DevDocs is itself a JS single-page app; this app disables
  /// JavaScript in every WebView on purpose -- see zim_webview.dart's own
  /// doc for why that's non-negotiable, so this can't rely on the
  /// archive's own JS to add one). Without it, Android's WebView falls
  //// back to treating the page as desktop content: a fixed ~980px virtual
  /// layout viewport, not scaled to fit the actual screen, so a "content
  /// column" the source CSS positions at some fixed offset renders
  /// squeezed into a small slice of the actual screen with the rest blank.
  ///
  /// `.zim` archives vary wildly in what HTML they contain (this is NOT
  /// special-cased to DevDocs, or any other specific generator) -- a
  /// missing/absent viewport tag is a generic, common omission across many
  /// real-world static sites and doc generators, so this applies to EVERY
  /// text/html response, unconditionally, and is a no-op (byte-identical
  /// passthrough) for any page that already declares one.
  List<int> _withViewportMeta(List<int> bytes) {
    String html;
    try {
      html = utf8.decode(bytes);
    } catch (_) {
      // Not valid UTF-8 (an unusual/legacy encoding) -- altering bytes
      // blindly risks corrupting it worse than a squeezed layout would;
      // leave it exactly as stored.
      return bytes;
    }
    if (_viewportMetaPattern.hasMatch(html)) return bytes;
    const tag = '<meta name="viewport" content="width=device-width, initial-scale=1">';
    final headMatch = _headOpenTagPattern.firstMatch(html);
    if (headMatch != null) {
      html = html.replaceRange(headMatch.end, headMatch.end, tag);
    } else {
      final htmlMatch = _htmlOpenTagPattern.firstMatch(html);
      final insertAt = htmlMatch?.end ?? 0;
      html = html.replaceRange(insertAt, insertAt, '<head>$tag</head>');
    }
    return utf8.encode(html);
  }

  static final _viewportMetaPattern = RegExp(
    r'''<meta[^>]+name\s*=\s*["']viewport["']''',
    caseSensitive: false,
  );
  static final _headOpenTagPattern = RegExp(r'<head[^>]*>', caseSensitive: false);
  static final _htmlOpenTagPattern = RegExp(r'<html[^>]*>', caseSensitive: false);

  void _setSecurityHeaders(HttpResponse response) {
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      // Archive HTML is untrusted. It may style itself and load its own
      // images/fonts/media, and -- only where allowScripts is true, see the
      // field doc -- run its own same-origin script and fetch its own
      // same-origin data. It can never reach the real network either way
      // (frame-src stays 'none', and 'self' everywhere else still only ever
      // resolves to this same loopback-only server); the WebView
      // controller's own JavaScriptMode is also still 'disabled' wherever
      // allowScripts is false, so this is defense in depth there, not the
      // only thing stopping scripts.
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline' data:; "
            "font-src 'self' data:; media-src 'self' data: blob:; script-src ${allowScripts ? "'self'" : "'none'"}; "
            "connect-src ${allowScripts ? "'self'" : "'none'"}; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'none'",
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
