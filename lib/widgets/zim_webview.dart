import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../providers/wiki_source.dart';
import '../zim/zim_local_server.dart';

/// Renders one .zim entry with a real browser engine -- Android via
/// webview_flutter, Windows via webview_windows (two different packages;
/// webview_flutter has no Windows implementation). Both point at a
/// loopback-only local HTTP server (lib/zim/zim_local_server.dart) that
/// serves the archive's own entries, so the browser resolves every
/// relative link/image/stylesheet itself with full CSS/table support --
/// the fidelity gap flutter_html (used as the Linux fallback, see
/// zim_html_view.dart, since no WebView plugin covers Linux) can't close.
///
/// JavaScript stays disabled on both platforms -- matches the web app's own
/// sandboxed iframe (`sandbox=""`, no `allow-scripts`) around .zim content:
/// some archives ship a client app that assumes capabilities an opaque
/// context doesn't have and breaks without them if half-executed, so never
/// running any of it is the one behavior that's uniformly correct for every
/// archive.
///
/// One server + one native WebView instance lives for as long as this
/// widget stays mounted (i.e. for the WikiViewerScreen's whole lifetime,
/// not per-page) -- navigating to a different entry calls loadUrl/
/// loadRequest on the existing controller, the same way a normal browser
/// tab navigates, instead of tearing down and recreating everything.
class ZimWebViewPage extends StatefulWidget {
  final ZimWikiSource source;
  final String path;
  final ValueChanged<String> onNavigate;

  const ZimWebViewPage({super.key, required this.source, required this.path, required this.onNavigate});

  @override
  State<ZimWebViewPage> createState() => _ZimWebViewPageState();
}

class _ZimWebViewPageState extends State<ZimWebViewPage> {
  ZimLocalServer? _server;
  wf.WebViewController? _androidController;
  ww.WebviewController? _windowsController;
  bool _windowsReady = false;
  String? _error;
  String? _loadedPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ZimWebViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) _loadPath(widget.path);
  }

  Future<void> _init() async {
    try {
      final server = ZimLocalServer(widget.source.archive);
      await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      _server = server;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final controller = wf.WebViewController()
          ..setJavaScriptMode(wf.JavaScriptMode.disabled)
          ..setNavigationDelegate(wf.NavigationDelegate(onNavigationRequest: _onNavigationRequest));
        setState(() => _androidController = controller);
        await _loadPath(widget.path);
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final controller = ww.WebviewController();
        await controller.initialize();
        if (!mounted) {
          controller.dispose();
          return;
        }
        controller.url.listen(_onWindowsUrlChanged);
        setState(() {
          _windowsController = controller;
          _windowsReady = true;
        });
        await _loadPath(widget.path);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadPath(String path) async {
    final server = _server;
    if (server == null) return;
    _loadedPath = path;
    final url = Uri.parse('${server.baseUrl}/${Uri.encodeFull(path)}');
    if (_androidController != null) {
      await _androidController!.loadRequest(url);
    } else if (_windowsController != null) {
      await _windowsController!.loadUrl(url.toString());
    }
  }

  wf.NavigationDecision _onNavigationRequest(wf.NavigationRequest request) {
    final handled = _handleNavigatedUrl(request.url);
    return handled ? wf.NavigationDecision.navigate : wf.NavigationDecision.prevent;
  }

  void _onWindowsUrlChanged(String url) => _handleNavigatedUrl(url);

  /// Returns whether [url] is one of our own local-server URLs. Same-server
  /// navigation is let through (the WebView loads it and we sync our own
  /// "current page" state from it); anything else -- an external http(s)
  /// link -- is refused, since this is a fully offline reader with no
  /// browser to hand it to.
  bool _handleNavigatedUrl(String url) {
    final server = _server;
    if (server == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != '127.0.0.1' || uri.port != server.port) return false;
    var path = uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty || path == _loadedPath) return true;
    _loadedPath = path;
    widget.onNavigate(path);
    return true;
  }

  @override
  void dispose() {
    _server?.stop();
    _windowsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not open this page: $_error'),
        ),
      );
    }
    if (_androidController != null) {
      return wf.WebViewWidget(controller: _androidController!);
    }
    if (_windowsReady && _windowsController != null) {
      return ww.Webview(_windowsController!);
    }
    return const Center(child: CircularProgressIndicator());
  }
}
