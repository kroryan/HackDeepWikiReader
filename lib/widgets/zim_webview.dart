import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

import '../providers/settings_provider.dart';
import '../providers/wiki_source.dart';
import '../utils/app_logger.dart';
import '../zim/zim_local_server.dart';

/// Renders one .zim entry with a real browser engine -- Android via the
/// official webview_flutter implementation, Linux via WebKitGTK, and Windows
/// via webview_windows. All point at a
/// loopback-only local HTTP server (lib/zim/zim_local_server.dart) that
/// serves the archive's own entries, so the browser resolves every
/// relative link/image/stylesheet itself with full CSS/table support --
/// browser gets the archive's intended CSS/table/flex/grid layout instead of
/// trying to approximate a web page with Flutter widgets.
///
/// JavaScript stays disabled on Linux and Windows -- matches the web app's
/// own sandboxed iframe (`sandbox=""`, no `allow-scripts`) around .zim
/// content: some archives ship a client app that assumes capabilities an
/// opaque context doesn't have and breaks without them if half-executed, so
/// never running any of it is the one behavior that's uniformly correct for
/// every archive on those platforms.
///
/// Android is the one exception, by explicit user decision: a real .zim
/// archive (a DevDocs export, confirmed live on a real device) turned out to
/// need its own JS to correctly collapse its sidebar into a mobile layout --
/// `._sidebar-hidden ._container{margin-left:0}` only every applies via a
/// class DevDocs' own script adds, no CSS media query does it. There is no
/// generic, content-agnostic CSS-only fix for "collapse whatever this
/// specific archive calls its sidebar" that doesn't special-case one
/// archive's markup at a time, so this is a real architecture trade-off, not
/// a guess: with the network fully cut off regardless (see
/// zim_local_server.dart's CSP -- connect-src/frame-src stay 'none' even
/// with scripts allowed, so nothing here can exfiltrate anything or reach
/// the network even if the archive's script tried), the main remaining risk
/// is a misbehaving archive's own script breaking half-executed within its
/// own sandboxed WebView, not a bigger blast radius elsewhere.
///
/// One server + one WebView instance lives for as long as this
/// widget stays mounted (i.e. for the WikiViewerScreen's whole lifetime,
/// not per-page) -- navigating to a different entry calls loadUrl/
/// loadRequest on the existing controller, the same way a normal browser
/// tab navigates, instead of tearing down and recreating everything.
class ZimWebViewPage extends StatefulWidget {
  final ZimWikiSource source;
  final String path;
  final ValueChanged<String> onNavigate;
  final bool visible;

  const ZimWebViewPage({
    super.key,
    required this.source,
    required this.path,
    required this.onNavigate,
    this.visible = true,
  });

  @override
  State<ZimWebViewPage> createState() => _ZimWebViewPageState();
}

class _ZimWebViewPageState extends State<ZimWebViewPage> {
  ZimLocalServer? _server;
  wf.WebViewController? _webController;
  ww.WebviewController? _windowsController;
  bool _windowsReady = false;
  String? _error;
  String? _loadedPath;
  Stopwatch? _pageLoadStopwatch;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ZimWebViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A click inside WebKit updates _loadedPath before notifying the parent.
    // When the parent rebuilds with that path, WebKit is already performing
    // the navigation; issuing loadRequest again here cancels/restarts the
    // policy decision and can leave the native view black. Drawer/index
    // selections have a different path than _loadedPath and still load.
    if (widget.path != oldWidget.path && widget.path != _loadedPath) {
      _loadPath(widget.path);
    }
  }

  double? _lastAppliedFontScale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-applies live if the user changes the font-size setting while this
    // .zim page is already open, not just on first load.
    final controller = _webController;
    if (controller == null) return;
    final fontScale = context.watch<SettingsProvider>().settings.fontScale;
    if (fontScale == _lastAppliedFontScale) return;
    unawaited(_applyTextZoom(controller));
  }

  Future<void> _applyTextZoom(wf.WebViewController controller) async {
    if (!mounted || controller.platform is! AndroidWebViewController) return;
    final fontScale = context.read<SettingsProvider>().settings.fontScale;
    _lastAppliedFontScale = fontScale;
    await (controller.platform as AndroidWebViewController)
        .setTextZoom((fontScale * 100).round());
  }

  Future<void> _init() async {
    try {
      final isAndroid = defaultTargetPlatform == TargetPlatform.android;
      final server = ZimLocalServer(widget.source.archive, allowScripts: isAndroid);
      await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      _server = server;

      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.linux) {
        final controller = wf.WebViewController()
          ..setJavaScriptMode(isAndroid ? wf.JavaScriptMode.unrestricted : wf.JavaScriptMode.disabled)
          ..setNavigationDelegate(
            wf.NavigationDelegate(
              onNavigationRequest: _onNavigationRequest,
              onPageStarted: (url) {
                _pageLoadStopwatch = Stopwatch()..start();
                AppLogger.instance.info('ZIM WebView started $url');
              },
              onPageFinished: (url) {
                final elapsed = _pageLoadStopwatch?.elapsedMilliseconds;
                _pageLoadStopwatch?.stop();
                AppLogger.instance.info(
                  'ZIM WebView finished ${elapsed ?? -1}ms $url',
                );
              },
              onWebResourceError: (error) {
                if (error.isForMainFrame == true && mounted) {
                  AppLogger.instance.warn(
                    'ZIM WebView main-frame error: ${error.description}',
                  );
                  setState(() => _error = error.description);
                }
              },
            ),
          );
        if (isAndroid && controller.platform is AndroidWebViewController) {
          // Generic, content-agnostic mitigation for archives whose own
          // responsive breakpoints assume a wider screen than an actual
          // phone -- confirmed live (a real DevDocs .zim, rotating the
          // device to landscape) that this exact page renders correctly
          // proportioned whenever the effective width is wide enough, and
          // that the archive's own JS never adds the narrow-viewport class
          // it would need to collapse otherwise (see zim_local_server.dart's
          // allowScripts doc). Rendering at a wider virtual viewport and
          // scaling the whole result down to fit the real screen (standard
          // Android WebView behavior for non-mobile-optimized sites, same
          // idea as loadWithOverviewMode, which is already on by default)
          // reproduces what landscape did automatically, without knowing
          // anything about this or any other specific archive's markup.
          await (controller.platform as AndroidWebViewController).setUseWideViewPort(true);
          // The app's font-size setting used to only reach Flutter-drawn
          // text (app_theme.dart) -- .zim page content renders through a
          // real WebView, entirely outside that theme, so it stayed fixed
          // regardless of the setting. setTextZoom scales exactly the way a
          // real mobile browser's own text-size setting does: it resizes
          // rendered text without breaking the page's own layout/CSS, unlike
          // naively multiplying font-size in injected CSS would.
          await _applyTextZoom(controller);
        }
        setState(() => _webController = controller);
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
    if (mounted) {
      setState(() {
        _error = null;
      });
    }
    final url = server.urlForPath(path);
    if (_webController != null) {
      await _webController!.loadRequest(url);
    } else if (_windowsController != null) {
      await _windowsController!.loadUrl(url.toString());
    }
  }

  wf.NavigationDecision _onNavigationRequest(wf.NavigationRequest request) {
    final handled = _handleNavigatedUrl(request.url);
    return handled
        ? wf.NavigationDecision.navigate
        : wf.NavigationDecision.prevent;
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
    if (uri == null || uri.host != '127.0.0.1' || uri.port != server.port) {
      return false;
    }
    final path = uri.pathSegments.join('/');
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
    if (_webController != null && widget.visible) {
      return wf.WebViewWidget(controller: _webController!);
    }
    if (_webController != null) {
      // On Linux a hidden native WebKit view means Flutter temporarily owns
      // this area (drawer or maximized chat). Avoid showing a misleading
      // perpetual loader behind those overlays.
      return const SizedBox.expand();
    }
    if (_windowsReady && _windowsController != null) {
      return ww.Webview(_windowsController!);
    }
    return const Center(child: CircularProgressIndicator());
  }
}
